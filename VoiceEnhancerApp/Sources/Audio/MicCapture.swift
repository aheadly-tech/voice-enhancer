import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os

/// Microphone capture + routing using `AVAudioEngine`.
///
/// Responsibilities:
///   * Set up an input node tap on a user-selected input device.
///   * For each captured buffer, call into the ``AudioEngineBridge`` to
///     process audio in place.
///   * Publish the processed audio into the shared-memory ring so the
///     virtual HAL driver (running inside coreaudiod) can serve it as a
///     microphone to any recording app.
///
/// Design notes:
///   * Mono processing. We take the first channel of the input and treat it
///     as the voice signal. Stereo mics (rare for voice work) get the left
///     channel only. This keeps the DSP path simple and matches how meeting
///     apps treat microphones anyway.
///   * Buffer size is 512 frames at 48 kHz (~10.7 ms). Good balance of
///     latency vs. CPU efficiency.
///   * Format conversion is handled by AVAudioEngine itself — we install
///     the tap with the ring's target format (48 kHz mono float32) and the
///     engine inserts an RT-safe converter in its audio graph when the
///     input device's native format differs.
final class MicCapture {
    /// AVAudioEngine can hand us much larger blocks than the requested tap
    /// buffer size during route changes and on some built-in devices. Keep
    /// ample headroom so those blocks don't get dropped before DSP.
    private static let maxProcessingFrames = 16_384

    private let logger = Logger(subsystem: "tech.aheadly.voice-enhancer", category: "MicCapture")
    private let engineBridge: AudioEngineBridge
    private let ringBridge: RingBufferBridge
    private let avEngine = AVAudioEngine()
    var engineConfigurationChangeHandler: (() -> Void)?

    /// Optional tap that receives raw pre-DSP audio (48 kHz mono float32).
    /// Used by VoicePreview to capture a test clip. RT-safe requirement:
    /// the closure must not allocate or lock.
    var rawAudioTap: ((UnsafePointer<Float>, Int) -> Void)?

    /// The target format the ring expects. Fixed: 48 kHz, mono, float32.
    /// The tap is installed with this format so AVAudioEngine handles any
    /// sample rate or channel conversion in its internal graph (RT-safe).
    private let ringFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
    }()

    /// Scratch buffer holding mono 48 kHz samples for DSP processing.
    /// Sized generously — some macOS input paths hand us ~4800-frame blocks
    /// even when the tap requests 512, and route changes can briefly grow that.
    private var processingBuffer = [Float](repeating: 0, count: MicCapture.maxProcessingFrames)

    private var tapInstalled = false
    private var engineConfigurationObserver: NSObjectProtocol?
    private var hasLoggedFirstInputBuffer = false

    init(engineBridge: AudioEngineBridge, ringBridge: RingBufferBridge) {
        self.engineBridge = engineBridge
        self.ringBridge = ringBridge
        self.engineConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: avEngine,
            queue: nil
        ) { [weak self] _ in
            self?.handleEngineConfigurationChange()
        }
    }

    deinit {
        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
    }

    // MARK: - Lifecycle

    /// Start capture.
    ///
    /// - Parameter deviceID: Optional Core Audio device ID to bind the input
    ///   to. Pass `nil` to use the system default. Passing a specific device
    ///   is how the user "picks a microphone" in the UI.
    ///
    /// Throws on permission denial, device binding failure, or engine setup
    /// failure.
    func start(deviceID: AudioDeviceID? = nil) async throws {
        try await requestMicrophonePermission()

        stop()

        if let id = deviceID {
            try bindInputDevice(id)
        }

        // The DSP engine always runs at the ring's rate (48 kHz mono).
        try engineBridge.prepare(
            sampleRate: ringFormat.sampleRate,
            maxBlockSize: Int32(Self.maxProcessingFrames)
        )

        // Mark a new writer session so the driver resyncs its read head.
        ringBridge.bumpGeneration()

        let input = avEngine.inputNode
        try installInputTap(on: input)

        try avEngine.start()
    }

    func stop() {
        if tapInstalled {
            removeInputTap()
            tapInstalled = false
        }
        avEngine.stop()
        hasLoggedFirstInputBuffer = false
    }

    // MARK: - Processing

    private func installInputTap(on input: AVAudioInputNode) throws {
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw MicCaptureError.invalidInputFormat
        }

        let prefersRingFormat =
            abs(nativeFormat.sampleRate - ringFormat.sampleRate) < 0.5 &&
            nativeFormat.channelCount == ringFormat.channelCount &&
            nativeFormat.commonFormat == ringFormat.commonFormat

        let initialFormat = prefersRingFormat ? ringFormat : nativeFormat
        do {
            try installTap(on: input, format: initialFormat)
        } catch {
            if prefersRingFormat {
                logger.warning("48 kHz mono tap failed; retrying with native input format: \(error.localizedDescription, privacy: .public)")
                try installTap(on: input, format: nativeFormat)
            } else {
                throw error
            }
        }

        logger.notice(
            "Input tap installed: \(nativeFormat.channelCount, privacy: .public)ch @ \(nativeFormat.sampleRate, privacy: .public) Hz native"
        )
    }

    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat) throws {
        let block: AVAudioNodeTapBlock = { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        #if VoiceEnhancerAppBundle
        var tapError: NSError?
        let ok = VEInstallInputTapSafely(input, 0, 512, format, block, &tapError)
        guard ok else {
            throw MicCaptureError.tapInstallationFailed(tapError?.localizedDescription ?? "Unknown AVAudioEngine tap failure.")
        }
        #else
        input.installTap(onBus: 0, bufferSize: 512, format: format, block: block)
        #endif
        tapInstalled = true
    }

    private func removeInputTap() {
        #if VoiceEnhancerAppBundle
        var tapError: NSError?
        if !VERemoveInputTapSafely(avEngine.inputNode, 0, &tapError) {
            logger.warning("Failed to remove input tap: \(tapError?.localizedDescription ?? "unknown error", privacy: .public)")
        }
        #else
        avEngine.inputNode.removeTap(onBus: 0)
        #endif
    }

    /// Handle one tapped input buffer on the audio thread.
    ///
    /// IMPORTANT: This runs on the audio thread. No allocations, no locks,
    /// no Swift concurrency. Anything non-trivial happens inside the C++
    /// engine or the lock-free ring. The buffer handling here is deliberately
    /// minimal.
    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, frameCount <= processingBuffer.count else { return }
        guard let channelData = buffer.floatChannelData else { return }

        if !hasLoggedFirstInputBuffer {
            hasLoggedFirstInputBuffer = true
            DispatchQueue.main.async { [weak self, frameCount] in
                self?.logger.notice("First input buffer: \(frameCount, privacy: .public) frames @ 48 kHz mono")
            }
        }

        processingBuffer.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            let processedFrames = copyFirstChannelToRingRate(
                channelData[0],
                sourceFrames: frameCount,
                sourceRate: buffer.format.sampleRate,
                destination: base,
                destinationCapacity: dst.count
            )
            guard processedFrames > 0 else { return }
            rawAudioTap?(UnsafePointer(base), processedFrames)
            engineBridge.process(buffer: base, numFrames: Int32(processedFrames))
            ringBridge.write(base, numFrames: Int32(processedFrames))
        }
    }

    private func copyFirstChannelToRingRate(
        _ source: UnsafePointer<Float>,
        sourceFrames: Int,
        sourceRate: Double,
        destination: UnsafeMutablePointer<Float>,
        destinationCapacity: Int
    ) -> Int {
        guard sourceRate > 0, sourceFrames > 0 else { return 0 }

        if abs(sourceRate - ringFormat.sampleRate) < 0.5 {
            let frames = min(sourceFrames, destinationCapacity)
            destination.update(from: source, count: frames)
            return frames
        }

        let outputFrames = min(
            destinationCapacity,
            max(1, Int((Double(sourceFrames) * ringFormat.sampleRate / sourceRate).rounded()))
        )
        let sourceStep = sourceRate / ringFormat.sampleRate
        for outIndex in 0..<outputFrames {
            let sourcePosition = Double(outIndex) * sourceStep
            let lowerIndex = min(Int(sourcePosition), sourceFrames - 1)
            let upperIndex = min(lowerIndex + 1, sourceFrames - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            destination[outIndex] = source[lowerIndex] + (source[upperIndex] - source[lowerIndex]) * fraction
        }
        return outputFrames
    }

    private func handleEngineConfigurationChange() {
        logger.notice("AVAudioEngine configuration changed; running=\(self.avEngine.isRunning, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.engineConfigurationChangeHandler?()
        }
    }

    // MARK: - Device binding

    /// Bind `avEngine.inputNode` to a specific Core Audio device.
    ///
    /// AVAudioEngine doesn't expose a "set input device" API directly on
    /// macOS — you set the underlying AUHAL unit's CurrentDevice property.
    /// Must be called before `avEngine.start()`; later changes require a
    /// full stop/start cycle to pick up.
    private func bindInputDevice(_ id: AudioDeviceID) throws {
        let audioUnit = avEngine.inputNode.audioUnit
        guard let unit = audioUnit else {
            throw MicCaptureError.deviceBindingFailed(code: -1)
        }
        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw MicCaptureError.deviceBindingFailed(code: Int(status))
        }
    }

    // MARK: - Permissions

    /// Request microphone permission asynchronously using a checked
    /// continuation. This avoids blocking the MainActor thread (which
    /// DispatchSemaphore.wait would do) and correctly suspends the Swift
    /// concurrency task until TCC responds.
    private func requestMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied, .restricted:
            throw MicCaptureError.microphonePermissionDenied
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    continuation.resume(returning: ok)
                }
            }
            if !granted { throw MicCaptureError.microphonePermissionDenied }
        @unknown default:
            throw MicCaptureError.microphonePermissionDenied
        }
    }
}

enum MicCaptureError: LocalizedError {
    case microphonePermissionDenied
    case deviceBindingFailed(code: Int)
    case invalidInputFormat
    case tapInstallationFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was not granted. Enable it in System Settings → Privacy & Security → Microphone."
        case .deviceBindingFailed(let code):
            return "Could not bind to the selected input device (code \(code))."
        case .invalidInputFormat:
            return "The selected microphone is not ready yet. Voice Enhancer will retry automatically."
        case .tapInstallationFailed(let message):
            return "Could not start microphone capture: \(message)"
        }
    }
}

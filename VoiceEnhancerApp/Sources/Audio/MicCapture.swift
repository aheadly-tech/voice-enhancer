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

        // Install a tap with the ring's target format. When the input
        // device's native format differs (e.g. 44.1 kHz stereo USB mic),
        // AVAudioEngine inserts an internal format converter that runs
        // inside its managed audio graph — RT-safe, no allocations in our
        // callback. The callback always receives 48 kHz mono float32.
        let input = avEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 512, format: ringFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        tapInstalled = true

        try avEngine.start()
    }

    func stop() {
        if tapInstalled {
            avEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        avEngine.stop()
        hasLoggedFirstInputBuffer = false
    }

    // MARK: - Processing

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

        // Copy channel 0 into the processing scratch buffer.
        // The tap is installed with ringFormat so the buffer is always
        // 48 kHz mono float32 — no conversion needed.
        processingBuffer.withUnsafeMutableBufferPointer { dst in
            guard let base = dst.baseAddress else { return }
            base.update(from: channelData[0], count: frameCount)
            rawAudioTap?(UnsafePointer(base), frameCount)
            engineBridge.process(buffer: base, numFrames: Int32(frameCount))
            ringBridge.write(base, numFrames: Int32(frameCount))
        }
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

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission was not granted. Enable it in System Settings → Privacy & Security → Microphone."
        case .deviceBindingFailed(let code):
            return "Could not bind to the selected input device (code \(code))."
        }
    }
}

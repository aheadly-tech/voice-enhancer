import AVFoundation
import os

/// Records a short voice clip and loops it through the DSP engine to the
/// system speakers so users can hear how parameter changes affect their voice.
final class VoicePreview {

    enum State: Equatable {
        case idle
        case recording(countdown: Int)
        case recorded
        case playing
    }

    private let logger = Logger(subsystem: "tech.aheadly.voice-enhancer", category: "VoicePreview")

    private static let sampleRate: Double = 48_000
    private static let recordSeconds = 3
    private static let maxFrames = Int(sampleRate) * recordSeconds

    // Pre-allocated recording buffer — writes are RT-safe (memcpy only).
    private var rawBuffer: [Float]
    private var recordedFrames = 0
    private var isCapturing = false

    // Playback engine (separate from the main capture engine).
    private var playbackEngine: AVAudioEngine?
    private let dspBridge = AudioEngineBridge()
    private var readPosition = 0

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?
    private var timers: [DispatchWorkItem] = []

    init() {
        rawBuffer = [Float](repeating: 0, count: Self.maxFrames)
    }

    // MARK: - Recording (called from audio thread)

    /// Append raw pre-DSP samples. RT-safe: no allocations, just memcpy.
    func captureAudio(_ samples: UnsafePointer<Float>, count: Int) {
        guard isCapturing else { return }
        let space = Self.maxFrames - recordedFrames
        guard space > 0 else { return }
        let n = min(count, space)
        rawBuffer.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.advanced(by: recordedFrames).update(from: samples, count: n)
        }
        recordedFrames += n
    }

    // MARK: - Controls (main thread)

    func startRecording() {
        stopPlayback()
        cancelTimers()
        recordedFrames = 0
        isCapturing = true
        setState(.recording(countdown: Self.recordSeconds))

        for i in 1..<Self.recordSeconds {
            schedule(after: i) { [weak self] in
                guard let self, self.isCapturing else { return }
                self.setState(.recording(countdown: Self.recordSeconds - i))
            }
        }
        schedule(after: Self.recordSeconds) { [weak self] in
            self?.finishRecording()
        }
    }

    func startPlayback(preset: Preset, compThresholdDb: Float,
                        deesserThresholdDb: Float, bypass: Bool) {
        guard recordedFrames > 0 else { return }
        isCapturing = false
        stopPlayback()

        do {
            try dspBridge.prepare(sampleRate: Self.sampleRate, maxBlockSize: 512)
        } catch {
            logger.error("Preview prepare failed: \(error.localizedDescription)")
            return
        }
        dspBridge.setPreset(preset)
        dspBridge.setBypass(bypass)
        dspBridge.setCompThresholdDb(compThresholdDb)
        dspBridge.setDeesserThresholdDb(deesserThresholdDb)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        )!

        readPosition = 0
        let totalFrames = recordedFrames
        let engine = AVAudioEngine()

        let sourceNode = AVAudioSourceNode(format: format) {
            [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else {
                let abl = UnsafeMutableAudioBufferListPointer(bufferList)
                if let d = abl[0].mData { memset(d, 0, Int(frameCount) * 4) }
                return noErr
            }
            let frames = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            self.rawBuffer.withUnsafeMutableBufferPointer { src in
                for i in 0..<frames {
                    out[i] = src[(self.readPosition + i) % totalFrames]
                }
            }
            self.readPosition = (self.readPosition + frames) % totalFrames
            self.dspBridge.process(buffer: out, numFrames: Int32(frames))
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            playbackEngine = engine
            setState(.playing)
        } catch {
            logger.error("Preview playback failed: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        if let engine = playbackEngine {
            engine.stop()
            playbackEngine = nil
        }
        if case .playing = state {
            setState(.recorded)
        }
    }

    func setCompThresholdDb(_ db: Float)    { dspBridge.setCompThresholdDb(db) }
    func setDeesserThresholdDb(_ db: Float)  { dspBridge.setDeesserThresholdDb(db) }
    func setPreset(_ preset: Preset)         { dspBridge.setPreset(preset) }
    func setBypass(_ bypass: Bool)           { dspBridge.setBypass(bypass) }

    func reset() {
        stopPlayback()
        cancelTimers()
        isCapturing = false
        recordedFrames = 0
        setState(.idle)
    }

    // MARK: - Private

    private func finishRecording() {
        isCapturing = false
        cancelTimers()
        setState(recordedFrames > 0 ? .recorded : .idle)
    }

    private func setState(_ s: State) {
        state = s
        onStateChange?(s)
    }

    private func schedule(after seconds: Int, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: item)
    }

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers.removeAll()
    }
}

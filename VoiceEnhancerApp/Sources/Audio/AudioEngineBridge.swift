import Foundation

// The C ABI (ve_engine_*, ve_ring_*) is exposed to Swift via the
// bridging header wired up in project.yml. When this target's Xcode build
// links libvoice_enhancer.a, project.yml sets the compilation condition
// `VoiceEnhancerEngine` so the real path below is active. When building
// with bare `swift build` (no bridging header, no static library), the
// stub path keeps the SwiftUI code compiling.
//
// Historical note: earlier revisions used `canImport(VoiceEnhancerEngine)`
// assuming a Swift module wrapper. The bridging-header path doesn't create
// a module, so we gate on the compilation condition directly.

/// Swift-side wrapper over the C ABI to the C++ DSP engine.
///
/// Responsibilities:
///   * Own the `ve_engine_t*` lifetime.
///   * Translate Swift types into the C ABI.
///   * Hide the `canImport` split: when building via Xcode the real engine
///     is linked, but `swift build` on the bare package uses a stub so the
///     Swift compile-check still passes without a C++ toolchain configured.
///
/// This type is intentionally not `ObservableObject`. It is a thin shim,
/// not a view model. ``AudioViewModel`` holds one and publishes from it.
final class AudioEngineBridge {

    #if VoiceEnhancerEngine
    private let handle: OpaquePointer?

    init() {
        self.handle = ve_engine_create()
    }

    deinit {
        if let h = handle {
            ve_engine_destroy(h)
        }
    }

    func prepare(sampleRate: Double, maxBlockSize: Int32) throws {
        guard let h = handle else { throw AudioEngineError.creationFailed }
        let status = ve_engine_prepare(h, sampleRate, maxBlockSize)
        if status != VE_OK {
            throw AudioEngineError.prepareFailed(code: Int(status.rawValue))
        }
    }

    func reset() {
        guard let h = handle else { return }
        ve_engine_reset(h)
    }

    func setPreset(_ preset: Preset) {
        guard let h = handle else { return }
        _ = ve_engine_set_preset(h, ve_preset_t(rawValue: UInt32(preset.rawValue)))
    }

    func setBypass(_ bypass: Bool) {
        guard let h = handle else { return }
        ve_engine_set_bypass(h, bypass ? 1 : 0)
    }

    func setInputGainDb(_ db: Float) {
        guard let h = handle else { return }
        ve_engine_set_input_gain_db(h, db)
    }

    func setOutputGainDb(_ db: Float) {
        guard let h = handle else { return }
        ve_engine_set_output_gain_db(h, db)
    }

    func setCompThresholdDb(_ db: Float) {
        guard let h = handle else { return }
        ve_engine_set_comp_threshold_db(h, db)
    }

    func setDeesserThresholdDb(_ db: Float) {
        guard let h = handle else { return }
        ve_engine_set_deesser_threshold_db(h, db)
    }

    /// Process a block in place. Called from the audio render thread.
    /// Performance-critical: no allocations, no Swift runtime calls inside
    /// the inner loop of the DSP engine (that lives in C++).
    func process(buffer: UnsafeMutablePointer<Float>, numFrames: Int32) {
        guard let h = handle else { return }
        _ = ve_engine_process(h, buffer, numFrames)
    }

    // Meters — lock-free atomic reads on the C++ side.
    func inputPeak()       -> Float { handle.map(ve_engine_get_input_peak) ?? 0 }
    func outputPeak()      -> Float { handle.map(ve_engine_get_output_peak) ?? 0 }
    func compressorGrDb()  -> Float { handle.map(ve_engine_get_compressor_gr_db) ?? 0 }
    func deesserGrDb()     -> Float { handle.map(ve_engine_get_deesser_gr_db) ?? 0 }

    #else
    // ----------------------------------------------------------------
    // Stub path — used by `swift build` when the C++ engine isn't in
    // the module search path. Lets us compile the SwiftUI code in CI
    // without a CMake build. The stub is silence-in, silence-out.
    // ----------------------------------------------------------------

    init() {}

    func prepare(sampleRate: Double, maxBlockSize: Int32) throws {}
    func reset() {}
    func setPreset(_ preset: Preset) {}
    func setBypass(_ bypass: Bool) {}
    func setInputGainDb(_ db: Float) {}
    func setOutputGainDb(_ db: Float) {}
    func setCompThresholdDb(_ db: Float) {}
    func setDeesserThresholdDb(_ db: Float) {}

    func process(buffer: UnsafeMutablePointer<Float>, numFrames: Int32) {
        // Pass-through — stub renders input unchanged.
    }

    func inputPeak() -> Float { 0 }
    func outputPeak() -> Float { 0 }
    func compressorGrDb() -> Float { 0 }
    func deesserGrDb() -> Float { 0 }
    #endif
}

enum AudioEngineError: LocalizedError {
    case creationFailed
    case prepareFailed(code: Int)

    var errorDescription: String? {
        switch self {
        case .creationFailed:            return "Failed to create audio engine."
        case .prepareFailed(let code):   return "Failed to prepare audio engine (code \(code))."
        }
    }
}

// ---------------------------------------------------------------------------
// Ring buffer bridge
//
// Owns the handle to the shared-memory ring used to hand processed audio
// off to the HAL driver (coreaudiod process). Mirrors the lifecycle split
// of AudioEngineBridge: a real path when the C engine is linked, a silent
// stub when building Swift-only.
//
// Thread model:
//   * init / deinit            — main thread.
//   * bumpGeneration / close   — main (or start/stop) thread.
//   * write / writable         — audio render thread. RT-safe.
// ---------------------------------------------------------------------------

final class RingBufferBridge {

    #if VoiceEnhancerEngine
    private let handle: OpaquePointer?

    /// Whether we have a live mapping. `false` means the driver bundle isn't
    /// installed or shared memory is otherwise unavailable — the app still
    /// runs, meters and monitoring work, just nothing is routed to the
    /// virtual device.
    var isOpen: Bool { handle != nil }

    init() {
        self.handle = ve_ring_open()
    }

    deinit {
        if let h = handle {
            ve_ring_close(h)
        }
    }

    /// Mark the start of a new writer session so the driver can detect
    /// that the app has (re)started and reset its read pointer.
    func bumpGeneration() {
        guard let h = handle else { return }
        ve_ring_bump_generation(h)
    }

    /// Publish `numFrames` float32 mono samples. RT-safe. Drops oldest
    /// audio on overrun — see RingBuffer.h for the rationale.
    func write(_ samples: UnsafePointer<Float>, numFrames: Int32) {
        guard let h = handle else { return }
        ve_ring_write(h, samples, numFrames)
    }

    /// How many frames of space currently free for writes. Mainly useful
    /// for surfacing IPC health in diagnostics UI.
    func writable() -> Int32 {
        guard let h = handle else { return 0 }
        return ve_ring_writable(h)
    }

    #else
    // Stub path mirrors AudioEngineBridge — lets `swift build` pass in CI.
    var isOpen: Bool { false }
    init() {}
    func bumpGeneration() {}
    func write(_ samples: UnsafePointer<Float>, numFrames: Int32) {}
    func writable() -> Int32 { 0 }
    #endif
}

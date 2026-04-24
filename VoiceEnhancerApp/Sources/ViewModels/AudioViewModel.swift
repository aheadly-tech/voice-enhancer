import Foundation
import SwiftUI
import Combine
import CoreAudio
import os

/// Main view model for the app.
///
/// Holds the audio pipeline (bridge + capture) and publishes state for the
/// UI. Everything the UI reads goes through `@Published` properties here —
/// views never touch the audio layer directly.
///
/// Thread model:
///   * Writes from the audio thread happen via polling: the bridge's atomic
///     meter values are polled by a Timer on the main thread at 60 Hz.
///   * Parameter changes (preset, bypass, gain) write through to the bridge
///     immediately. The bridge queues them atomically.
@MainActor
final class AudioViewModel: ObservableObject {
    private let logger = Logger(subsystem: "tech.aheadly.voice-enhancer", category: "AudioViewModel")

    // MARK: - Published state

    /// Currently active preset. Writing triggers an engine preset swap and
    /// resets the tuning sliders to the preset's defaults.
    @Published var selectedPreset: Preset = .natural {
        didSet {
            guard oldValue != selectedPreset else { return }
            bridge.setPreset(selectedPreset)
            compThresholdDb = selectedPreset.defaultCompThresholdDb
            deesserThresholdDb = selectedPreset.defaultDeesserThresholdDb
        }
    }

    /// Compressor threshold in dB. Lower = more compression.
    @Published var compThresholdDb: Float = Preset.natural.defaultCompThresholdDb {
        didSet {
            bridge.setCompThresholdDb(compThresholdDb)
            preview.setCompThresholdDb(compThresholdDb)
        }
    }

    /// De-esser threshold in dB. Lower = more sibilance reduction.
    @Published var deesserThresholdDb: Float = Preset.natural.defaultDeesserThresholdDb {
        didSet {
            bridge.setDeesserThresholdDb(deesserThresholdDb)
            preview.setDeesserThresholdDb(deesserThresholdDb)
        }
    }

    /// Voice preview state for the Settings UI.
    @Published private(set) var previewState: VoicePreview.State = .idle

    /// Global enhancement toggle. When false, the engine is bypassed.
    @Published var isEnabled: Bool = true {
        didSet {
            bridge.setBypass(!isEnabled)
        }
    }

    /// Human-readable status string shown in the toolbar.
    @Published private(set) var status: Status = .idle

    /// Whether the shared-memory ring to the HAL driver is open. False when
    /// the driver bundle isn't installed (or the OS denied the mapping) —
    /// the app still runs, just without routing audio to the virtual mic.
    @Published private(set) var driverAvailable: Bool = false

    /// Every input device currently visible to the HAL. Refreshed on
    /// `refreshDeviceList()`, which the settings sheet calls on appear.
    @Published private(set) var inputDevices: [AudioDevice] = []

    /// Persisted UID of the user-selected input device, or nil to use the
    /// system default. Writing triggers an audio restart on the next
    /// `start()` call. We persist the UID (not the AudioDeviceID) because
    /// UIDs survive unplug/replug and reboots.
    @Published var selectedInputUID: String? {
        didSet {
            guard oldValue != selectedInputUID else { return }
            UserDefaults.standard.set(selectedInputUID, forKey: Self.inputUIDDefaultsKey)
            // Hot-swap: restart the capture graph with the new device.
            Task { await restartCaptureIfRunning() }
        }
    }

    private static let inputUIDDefaultsKey = "tech.aheadly.voice-enhancer.inputUID"

    // Meter values, updated at 60 Hz from `startMeterPolling()` through the
    // peak-hold smoother in `pollMeters()`. Peak meters are in [0, 1] linear
    // (post-smoothing); GR values are in dB and are negative when the
    // corresponding compressor is engaging.
    @Published private(set) var inputPeak:       Float = 0
    @Published private(set) var outputPeak:      Float = 0
    @Published private(set) var compressorGrDb:  Float = 0
    @Published private(set) var deesserGrDb:     Float = 0

    // MARK: - Internals

    private let bridge: AudioEngineBridge
    private let ring: RingBufferBridge
    private let capture: MicCapture
    private let preview = VoicePreview()
    private var meterTimer: Timer?
    private var configurationRestartTask: Task<Void, Never>?
    private var configurationStabilityTask: Task<Void, Never>?
    private var desiredRunningState = false
    private var configurationRestartAttempts = 0

    private static let maxConfigurationRestartAttempts = 3

    // MARK: - Init

    init() {

        let bridge = AudioEngineBridge()
        let ring = RingBufferBridge()
        self.bridge = bridge
        self.ring = ring
        self.capture = MicCapture(engineBridge: bridge, ringBridge: ring)
        self.capture.engineConfigurationChangeHandler = { [weak self] in
            Task { @MainActor in
                await self?.handleCaptureConfigurationChange()
            }
        }
        self.inputDevices = AudioDeviceEnumerator.listInputDevices()
        self.driverAvailable = AudioDeviceEnumerator.hasVoiceEnhancerDriver() || ring.isOpen
        self.selectedInputUID = UserDefaults.standard.string(forKey: Self.inputUIDDefaultsKey)

        // Wire preview: tap raw audio from capture, publish state changes.
        let prev = self.preview
        self.capture.rawAudioTap = { [weak prev] samples, count in
            prev?.captureAudio(samples, count: count)
        }
        prev.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.previewState = state
            }
        }
    }

    // MARK: - Lifecycle

    func start() async {

        desiredRunningState = true
        await startCaptureGraph()
    }

    func stop() {
        desiredRunningState = false
        configurationRestartTask?.cancel()
        configurationRestartTask = nil
        configurationStabilityTask?.cancel()
        configurationStabilityTask = nil
        configurationRestartAttempts = 0
        stopCaptureGraph(updateStatus: true)
    }

    /// Restart the capture graph. Used when the user switches input devices
    /// or the device list changes. No-op when the graph isn't running.
    private func restartCaptureIfRunning() async {
        guard desiredRunningState else { return }
        stopCaptureGraph(updateStatus: false)
        await startCaptureGraph()
    }

    private func startCaptureGraph() async {

        logger.notice("startCaptureGraph called")
        status = .starting
        refreshDeviceList()

        do {
            // Resolve the persisted UID to a live device ID. If the device
            // went away, fall through to the system default rather than
            // failing the start.
            let deviceID = selectedInputUID.flatMap(AudioDeviceEnumerator.deviceID(forUID:))

            try await capture.start(deviceID: deviceID)

            startMeterPolling()
            configurationRestartTask?.cancel()
            configurationRestartTask = nil
            status = .running
            scheduleConfigurationRestartBudgetReset()
        } catch {

            desiredRunningState = false
            status = .failed(error.localizedDescription)
            logger.error("startCaptureGraph failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopCaptureGraph(updateStatus: Bool) {
        capture.stop()
        stopMeterPolling()
        inputPeak = 0
        outputPeak = 0
        compressorGrDb = 0
        deesserGrDb = 0
        if updateStatus {
            status = .idle
        }
    }

    private func handleCaptureConfigurationChange() async {
        guard desiredRunningState else { return }
        guard configurationRestartTask == nil else { return }

        configurationStabilityTask?.cancel()
        configurationStabilityTask = nil
        configurationRestartAttempts += 1
        guard configurationRestartAttempts <= Self.maxConfigurationRestartAttempts else {
            logger.error("Capture graph exceeded configuration restart budget")
            desiredRunningState = false
            stopCaptureGraph(updateStatus: false)
            status = .failed("Audio device kept reconfiguring. Reopen the app or reselect the microphone.")
            return
        }

        logger.notice("Restarting capture after engine configuration change (attempt \(self.configurationRestartAttempts, privacy: .public))")
        status = .starting
        configurationRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.restartAfterConfigurationChange()
        }
    }

    private func restartAfterConfigurationChange() async {
        defer { configurationRestartTask = nil }
        guard desiredRunningState else { return }
        stopCaptureGraph(updateStatus: false)
        await startCaptureGraph()
    }

    private func scheduleConfigurationRestartBudgetReset() {
        configurationStabilityTask?.cancel()
        configurationStabilityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                self?.resetConfigurationRestartBudget()
            }
        }
    }

    private func resetConfigurationRestartBudget() {
        guard desiredRunningState, status == .running else { return }
        configurationRestartAttempts = 0
        configurationStabilityTask = nil
    }

    // MARK: - Voice Preview

    func startPreviewRecording() { preview.startRecording() }

    func startPreviewPlayback() {
        preview.startPlayback(
            preset: selectedPreset,
            compThresholdDb: compThresholdDb,
            deesserThresholdDb: deesserThresholdDb,
            bypass: !isEnabled
        )
    }

    func stopPreviewPlayback() { preview.stopPlayback() }
    func resetPreview() { preview.reset() }

    // MARK: - Devices

    /// Rebuild the visible input device list. Call from the UI on settings
    /// sheet appear (and, optionally, on HAL property change notifications).
    func refreshDeviceList() {
        inputDevices = AudioDeviceEnumerator.listInputDevices()
        driverAvailable = AudioDeviceEnumerator.hasVoiceEnhancerDriver() || ring.isOpen
    }

    // MARK: - Meters

    private func startMeterPolling() {
        // 60 Hz matches typical display refresh. Peak-hold ballistics below
        // need a steady tick so the decay animates during silence — a
        // `.onChange` driven smoother would freeze at the last value when
        // nothing new is arriving.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollMeters() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.meterTimer = timer
        // Reset smoother state so a fresh start doesn't inherit stale tails.
        smoothedInputPeak = 0
        smoothedOutputPeak = 0
        smoothedCompressorGrDb = 0
        smoothedDeesserGrDb = 0
    }

    private func stopMeterPolling() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // Peak-hold ballistics state. Smoothed values drive the UI; raw values
    // from the engine are latched per-block and can be twitchy at 60 Hz.
    private var smoothedInputPeak: Float = 0
    private var smoothedOutputPeak: Float = 0
    private var smoothedCompressorGrDb: Float = 0
    private var smoothedDeesserGrDb: Float = 0

    // Attack/release coefficients for the meter smoother, tuned for a 60 Hz
    // poll. 1.0 on attack means "snap to the new peak instantly"; the release
    // coefficient gives a visible hang-and-fall that lets the eye register a
    // transient without lingering forever.
    private static let peakAttackAlpha: Float = 1.0      // instant rise
    private static let peakReleaseAlpha: Float = 0.15    // ~6-tick decay
    private static let grAttackAlpha: Float = 0.6        // snappy on compression
    private static let grReleaseAlpha: Float = 0.08      // slow hang when GR eases

    private func pollMeters() {
        // Raw reads are lock-free atomics on the engine side — safe to call
        // from any thread, we just happen to be on main here.
        let rawInput  = bridge.inputPeak()
        let rawOutput = bridge.outputPeak()
        let rawComp   = bridge.compressorGrDb()
        let rawDees   = bridge.deesserGrDb()

        // Peak meters: fast attack, slow release.
        smoothedInputPeak  = Self.smoothPeak(
            current: smoothedInputPeak, target: rawInput,
            attack: Self.peakAttackAlpha, release: Self.peakReleaseAlpha
        )
        smoothedOutputPeak = Self.smoothPeak(
            current: smoothedOutputPeak, target: rawOutput,
            attack: Self.peakAttackAlpha, release: Self.peakReleaseAlpha
        )

        // GR meters: raw values are negative dB. "More negative" is more
        // compression, so we treat that as the "rising" direction.
        smoothedCompressorGrDb = Self.smoothGr(
            current: smoothedCompressorGrDb, target: rawComp,
            attack: Self.grAttackAlpha, release: Self.grReleaseAlpha
        )
        smoothedDeesserGrDb = Self.smoothGr(
            current: smoothedDeesserGrDb, target: rawDees,
            attack: Self.grAttackAlpha, release: Self.grReleaseAlpha
        )

        inputPeak       = smoothedInputPeak
        outputPeak      = smoothedOutputPeak
        compressorGrDb  = smoothedCompressorGrDb
        deesserGrDb     = smoothedDeesserGrDb
    }

    /// One-pole smoother with asymmetric attack/release for positive peak
    /// values. On attack (target ≥ current) we use the faster coefficient.
    private static func smoothPeak(current: Float, target: Float,
                                   attack: Float, release: Float) -> Float {
        let alpha = target >= current ? attack : release
        return current + alpha * (target - current)
    }

    /// Same idea as smoothPeak but for negative dB values where "more
    /// negative" is the rising direction (more compression).
    private static func smoothGr(current: Float, target: Float,
                                 attack: Float, release: Float) -> Float {
        let alpha = target <= current ? attack : release
        return current + alpha * (target - current)
    }

    // MARK: - Status

    enum Status: Equatable {
        case idle
        case starting
        case running
        case failed(String)

        var displayText: String {
            switch self {
            case .idle:            return "Idle"
            case .starting:        return "Starting…"
            case .running:         return "Running"
            case .failed(let msg): return "Error: \(msg)"
            }
        }

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }
}

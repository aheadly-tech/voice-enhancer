import Foundation
import SwiftUI
import Combine
import CoreAudio
import AppKit
import ServiceManagement
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
            UserDefaults.standard.set(selectedPreset.rawValue, forKey: Self.presetDefaultsKey)
            applySelectedPreset()
        }
    }

    /// Compressor threshold in dB. Lower = more compression.
    @Published var compThresholdDb: Float = Preset.natural.defaultCompThresholdDb {
        didSet {
            bridge.setCompThresholdDb(compThresholdDb)
            preview.setCompThresholdDb(compThresholdDb)
            UserDefaults.standard.set(compThresholdDb, forKey: Self.compThresholdDefaultsKey)
            persistManualTuningIfNeeded()
        }
    }

    /// De-esser threshold in dB. Lower = more sibilance reduction.
    @Published var deesserThresholdDb: Float = Preset.natural.defaultDeesserThresholdDb {
        didSet {
            bridge.setDeesserThresholdDb(deesserThresholdDb)
            preview.setDeesserThresholdDb(deesserThresholdDb)
            UserDefaults.standard.set(deesserThresholdDb, forKey: Self.deesserThresholdDefaultsKey)
            persistManualTuningIfNeeded()
        }
    }

    /// Voice preview state for the Settings UI.
    @Published private(set) var previewState: VoicePreview.State = .idle

    /// User-selected app language. Applied immediately to SwiftUI views and
    /// persisted locally so the app opens in the same language next time.
    @Published var appLanguage: AppLanguage = .preferred() {
        didSet {
            guard oldValue != appLanguage else { return }
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Self.appLanguageDefaultsKey)
        }
    }

    /// Global enhancement toggle. When false, the engine is bypassed.
    @Published var isEnabled: Bool = true {
        didSet {
            bridge.setBypass(!isEnabled)
            UserDefaults.standard.set(isEnabled, forKey: Self.processingEnabledDefaultsKey)
        }
    }

    /// Mirrors the macOS Login Items registration for the main app.
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin, !isSyncingLaunchAtLogin else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    @Published private(set) var launchAtLoginError: String?

    /// Human-readable status string shown in the toolbar.
    @Published private(set) var status: Status = .idle {
        didSet {
            Self.updateDockBadge(for: status)
        }
    }

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
            if let selectedInputUID {
                UserDefaults.standard.set(selectedInputUID, forKey: Self.inputUIDDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.inputUIDDefaultsKey)
            }
            // Hot-swap: restart the capture graph with the new device.
            Task { await scheduleReconnect(reason: "input device changed", delaySeconds: 0.2) }
        }
    }

    private static let inputUIDDefaultsKey = "tech.aheadly.voice-enhancer.inputUID"
    private static let presetDefaultsKey = "tech.aheadly.voice-enhancer.preset"
    private static let compThresholdDefaultsKey = "tech.aheadly.voice-enhancer.compThresholdDb"
    private static let deesserThresholdDefaultsKey = "tech.aheadly.voice-enhancer.deesserThresholdDb"
    private static let customCompThresholdDefaultsKey = "tech.aheadly.voice-enhancer.customCompThresholdDb"
    private static let customDeesserThresholdDefaultsKey = "tech.aheadly.voice-enhancer.customDeesserThresholdDb"
    private static let processingEnabledDefaultsKey = "tech.aheadly.voice-enhancer.processingEnabled"
    private static let appLanguageDefaultsKey = "tech.aheadly.voice-enhancer.appLanguage"

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
    private var reconnectTask: Task<Void, Never>?
    private var desiredRunningState = false
    private var isReconnecting = false
    private var isApplyingPresetSelection = false
    private var isPromotingManualTuningToCustom = false
    private var isSyncingLaunchAtLogin = false
    private var wakeObserver: NSObjectProtocol?

    private static let reconnectBackoffSeconds: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        5_000_000_000
    ]

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
        self.selectedInputUID = Self.loadSelectedInputUID()
        let loadedPreset = Self.loadPreset()
        self.selectedPreset = loadedPreset
        self.compThresholdDb = Self.loadFloat(
            forKey: loadedPreset == .custom ? Self.customCompThresholdDefaultsKey : Self.compThresholdDefaultsKey,
            defaultValue: loadedPreset.defaultCompThresholdDb
        )
        self.deesserThresholdDb = Self.loadFloat(
            forKey: loadedPreset == .custom ? Self.customDeesserThresholdDefaultsKey : Self.deesserThresholdDefaultsKey,
            defaultValue: loadedPreset.defaultDeesserThresholdDb
        )
        self.appLanguage = Self.loadAppLanguage()
        self.isEnabled = Self.loadBool(forKey: Self.processingEnabledDefaultsKey, defaultValue: true)
        self.isSyncingLaunchAtLogin = true
        self.launchAtLogin = Self.isLaunchAtLoginEnabled()
        self.isSyncingLaunchAtLogin = false

        bridge.setPreset(selectedPreset)
        bridge.setCompThresholdDb(compThresholdDb)
        preview.setCompThresholdDb(compThresholdDb)
        bridge.setDeesserThresholdDb(deesserThresholdDb)
        preview.setDeesserThresholdDb(deesserThresholdDb)
        bridge.setBypass(!isEnabled)

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

        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.scheduleReconnect(reason: "system woke from sleep", delaySeconds: 3.0)
            }
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Lifecycle

    func start() async {

        if desiredRunningState, status == .running {
            return
        }
        desiredRunningState = true
        await startCaptureGraph()
    }

    func stop() {
        desiredRunningState = false
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        stopCaptureGraph(updateStatus: true)
    }

    func toggleProcessing() {
        isEnabled.toggle()
    }

    func reconnectMicrophone() {
        Task {
            await scheduleReconnect(reason: "manual reconnect", delaySeconds: 0)
        }
    }

    func t(_ key: LocalizedStrings.Key) -> String {
        LocalizedStrings.text(key, language: appLanguage)
    }

    func t(_ key: LocalizedStrings.Key, _ values: CVarArg...) -> String {
        LocalizedStrings.text(key, language: appLanguage, arguments: values)
    }

    func refreshLaunchAtLoginStatus() {
        isSyncingLaunchAtLogin = true
        launchAtLogin = Self.isLaunchAtLoginEnabled()
        isSyncingLaunchAtLogin = false
    }

    private func startCaptureGraph() async {

        logger.notice("startCaptureGraph called")
        status = .starting

        do {
            try await beginCaptureGraph()
            reconnectTask?.cancel()
            reconnectTask = nil
            status = .running
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
        await scheduleReconnect(reason: "audio device configuration changed")
    }

    private func scheduleReconnect(reason: String, delaySeconds: Double = 1.5) async {
        guard desiredRunningState else { return }
        guard !isReconnecting else {
            logger.notice("Reconnect already in progress; coalescing event: \(reason, privacy: .public)")
            return
        }
        reconnectTask?.cancel()
        let delayNanos = UInt64(max(0, delaySeconds) * 1_000_000_000)
        logger.notice("Scheduling audio reconnect after \(delaySeconds, privacy: .public)s: \(reason, privacy: .public)")
        status = .starting
        reconnectTask = Task { [weak self] in
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            guard !Task.isCancelled else { return }
            await self?.performReconnect(reason: reason)
        }
    }

    private func performReconnect(reason: String) async {
        guard desiredRunningState, !isReconnecting else { return }
        isReconnecting = true
        defer {
            isReconnecting = false
            reconnectTask = nil
        }

        logger.notice("Reconnecting audio engine: \(reason, privacy: .public)")
        status = .starting

        var lastError: Error?
        for attempt in 0...Self.reconnectBackoffSeconds.count {
            stopCaptureGraph(updateStatus: false)
            do {
                try await beginCaptureGraph()
                status = .running
                logger.notice("Audio reconnect succeeded")
                return
            } catch {
                lastError = error
                logger.error("Audio reconnect attempt \(attempt + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                if attempt < Self.reconnectBackoffSeconds.count {
                    try? await Task.sleep(nanoseconds: Self.reconnectBackoffSeconds[attempt])
                    if Task.isCancelled { return }
                }
            }
        }

        let message = lastError?.localizedDescription ?? "Unknown audio restart failure."
        status = .failed("Could not reconnect microphone automatically. Use Restart Audio Engine from the menu. \(message)")
    }

    private func beginCaptureGraph() async throws {
        refreshDeviceList()

        let deviceID: AudioDeviceID?
        if let selectedInputUID, let liveDeviceID = AudioDeviceEnumerator.deviceID(forUID: selectedInputUID) {
            deviceID = liveDeviceID
            logger.notice("Starting capture with selected input UID: \(selectedInputUID, privacy: .public)")
        } else if selectedInputUID != nil {
            deviceID = inputDevices.first?.deviceID
            logger.warning("Persisted input device is unavailable; temporarily falling back to first input device")
        } else {
            deviceID = nil
            logger.notice("Starting capture with system default input")
        }

        try await capture.start(deviceID: deviceID)
        startMeterPolling()
    }

    private func applySelectedPreset() {
        if selectedPreset == .custom {
            guard !isPromotingManualTuningToCustom else { return }
            isApplyingPresetSelection = true
            compThresholdDb = Self.loadFloat(
                forKey: Self.customCompThresholdDefaultsKey,
                defaultValue: compThresholdDb
            )
            deesserThresholdDb = Self.loadFloat(
                forKey: Self.customDeesserThresholdDefaultsKey,
                defaultValue: deesserThresholdDb
            )
            isApplyingPresetSelection = false
            return
        }

        isApplyingPresetSelection = true
        bridge.setPreset(selectedPreset)
        compThresholdDb = selectedPreset.defaultCompThresholdDb
        deesserThresholdDb = selectedPreset.defaultDeesserThresholdDb
        isApplyingPresetSelection = false
    }

    private func persistManualTuningIfNeeded() {
        guard !isApplyingPresetSelection else { return }

        if selectedPreset != .custom {
            isPromotingManualTuningToCustom = true
            selectedPreset = .custom
            isPromotingManualTuningToCustom = false
        }

        UserDefaults.standard.set(compThresholdDb, forKey: Self.customCompThresholdDefaultsKey)
        UserDefaults.standard.set(deesserThresholdDb, forKey: Self.customDeesserThresholdDefaultsKey)
    }

    private static func loadSelectedInputUID() -> String? {
        UserDefaults.standard.string(forKey: inputUIDDefaultsKey)
    }

    private static func loadPreset() -> Preset {
        let raw = UserDefaults.standard.integer(forKey: presetDefaultsKey)
        return Preset(rawValue: raw) ?? .natural
    }

    private static func loadFloat(forKey key: String, defaultValue: Float) -> Float {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.float(forKey: key)
    }

    private static func loadBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func loadAppLanguage() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: appLanguageDefaultsKey) else {
            return .preferred()
        }
        return AppLanguage(rawValue: raw) ?? .preferred()
    }

    private static func updateDockBadge(for status: Status) {
        NSApp.dockTile.badgeLabel = status.isError ? "!" : nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginError = error.localizedDescription
            logger.error("Failed to update launch-at-login: \(error.localizedDescription, privacy: .public)")
            refreshLaunchAtLoginStatus()
        }
    }

    private static func isLaunchAtLoginEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
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

        func displayText(language: AppLanguage) -> String {
            switch self {
            case .idle:
                return LocalizedStrings.text(.idle, language: language)
            case .starting:
                return LocalizedStrings.text(.starting, language: language)
            case .running:
                return LocalizedStrings.text(.running, language: language)
            case .failed(let msg):
                return LocalizedStrings.text(.errorPrefix, language: language, msg)
            }
        }

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }
}

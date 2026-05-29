import Foundation

/// Voice-processing preset — the user's main choice in the UI.
///
/// Factory preset raw values must stay in sync with `ve_preset_t` in the C
/// ABI header and with `PresetId` in the C++ engine. `custom` is Swift-only:
/// it preserves user slider choices on top of the current engine tuning.
///
/// When adding a factory preset:
///   1. Add the case in C++ (``AudioEngine/include/voice_enhancer/Preset.h``)
///   2. Add it to ``ve_preset_t`` in the C ABI
///   3. Add it here
///   4. Add tuning values in ``AudioEngine/src/Preset.cpp``
enum Preset: Int, CaseIterable, Identifiable {
    case natural   = 0
    case broadcast = 1
    case clarity   = 2
    case warm      = 3
    case custom    = 4

    var id: Int { rawValue }

    var isFactoryPreset: Bool {
        self != .custom
    }

    /// Short display name shown on the preset card.
    var name: String {
        name(language: .english)
    }

    func name(language: AppLanguage) -> String {
        switch self {
        case .natural:   return LocalizedStrings.text(.naturalName, language: language)
        case .broadcast: return LocalizedStrings.text(.broadcastName, language: language)
        case .clarity:   return LocalizedStrings.text(.clarityName, language: language)
        case .warm:      return LocalizedStrings.text(.warmName, language: language)
        case .custom:    return LocalizedStrings.text(.customName, language: language)
        }
    }

    /// One-line description of what the preset does. Kept deliberately short
    /// so it fits comfortably under the name on a preset card.
    var blurb: String {
        blurb(language: .english)
    }

    func blurb(language: AppLanguage) -> String {
        switch self {
        case .natural:   return LocalizedStrings.text(.naturalBlurb, language: language)
        case .broadcast: return LocalizedStrings.text(.broadcastBlurb, language: language)
        case .clarity:   return LocalizedStrings.text(.clarityBlurb, language: language)
        case .warm:      return LocalizedStrings.text(.warmBlurb, language: language)
        case .custom:    return LocalizedStrings.text(.customBlurb, language: language)
        }
    }

    /// SF Symbol used as the preset card's icon.
    var systemImage: String {
        switch self {
        case .natural:   return "waveform"
        case .broadcast: return "dot.radiowaves.left.and.right"
        case .clarity:   return "sparkles"
        case .warm:      return "flame"
        case .custom:    return "slider.horizontal.3"
        }
    }

    /// Default compressor threshold for this preset (dB). Keep in sync with Preset.cpp.
    var defaultCompThresholdDb: Float {
        switch self {
        case .natural:   return -18
        case .broadcast: return -22
        case .clarity:   return -20
        case .warm:      return -18
        case .custom:    return -18
        }
    }

    /// Default de-esser threshold for this preset (dB). Keep in sync with Preset.cpp.
    var defaultDeesserThresholdDb: Float {
        switch self {
        case .natural:   return -24
        case .broadcast: return -26
        case .clarity:   return -24
        case .warm:      return -26
        case .custom:    return -24
        }
    }
}

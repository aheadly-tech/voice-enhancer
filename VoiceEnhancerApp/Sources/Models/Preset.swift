import Foundation

/// Voice-processing preset — the user's main choice in the UI.
///
/// Values here must stay in sync with `ve_preset_t` in the C ABI header and
/// with `PresetId` in the C++ engine. When adding a preset:
///   1. Add the case in C++ (``AudioEngine/include/voice_enhancer/Preset.h``)
///   2. Add it to ``ve_preset_t`` in the C ABI
///   3. Add it here
///   4. Add tuning values in ``AudioEngine/src/Preset.cpp``
enum Preset: Int, CaseIterable, Identifiable {
    case natural   = 0
    case broadcast = 1
    case clarity   = 2
    case warm      = 3

    var id: Int { rawValue }

    /// Short display name shown on the preset card.
    var name: String {
        switch self {
        case .natural:   return "Natural"
        case .broadcast: return "Broadcast"
        case .clarity:   return "Clarity"
        case .warm:      return "Warm"
        }
    }

    /// One-line description of what the preset does. Kept deliberately short
    /// so it fits comfortably under the name on a preset card.
    var blurb: String {
        switch self {
        case .natural:   return "Gentle cleanup. Most transparent."
        case .broadcast: return "Radio DJ voice. Bold and clear."
        case .clarity:   return "Cuts through. Great for quiet mics."
        case .warm:      return "Softens harsh mics. Adds body."
        }
    }

    /// SF Symbol used as the preset card's icon.
    var systemImage: String {
        switch self {
        case .natural:   return "waveform"
        case .broadcast: return "dot.radiowaves.left.and.right"
        case .clarity:   return "sparkles"
        case .warm:      return "flame"
        }
    }

    /// Default compressor threshold for this preset (dB). Keep in sync with Preset.cpp.
    var defaultCompThresholdDb: Float {
        switch self {
        case .natural:   return -18
        case .broadcast: return -22
        case .clarity:   return -20
        case .warm:      return -18
        }
    }

    /// Default de-esser threshold for this preset (dB). Keep in sync with Preset.cpp.
    var defaultDeesserThresholdDb: Float {
        switch self {
        case .natural:   return -24
        case .broadcast: return -26
        case .clarity:   return -24
        case .warm:      return -26
        }
    }
}

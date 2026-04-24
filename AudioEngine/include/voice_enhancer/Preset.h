#ifndef VOICE_ENHANCER_PRESET_H
#define VOICE_ENHANCER_PRESET_H

#include "voice_enhancer/Types.h"
#include "voice_enhancer/dsp/ParametricEQ.h"

namespace voice_enhancer {

// The four preset identities shipped in v1. Keep these in sync with the
// Swift enum in VoiceEnhancerApp/Sources/Models/Preset.swift.
enum class PresetId : int {
    Natural   = 0,
    Broadcast = 1,
    Clarity   = 2,
    Warm      = 3,
};

// All tunable parameters that define a preset. We choose flat structs over
// "an Engine subclass per preset" because presets are data, not behavior.
struct PresetConfig {
    // High-pass filter
    Sample hpf_cutoff_hz;

    // Compressor
    Sample comp_threshold_db;
    Sample comp_ratio;
    Sample comp_knee_db;
    Sample comp_attack_ms;
    Sample comp_release_ms;

    // 4-band EQ
    dsp::ParametricEQ::BandConfig eq_bands[dsp::ParametricEQ::BandCount];

    // De-esser
    Sample deesser_crossover_hz;
    Sample deesser_threshold_db;
    Sample deesser_ratio;
    Sample deesser_max_reduction_db;

    // Output
    Sample output_gain_db;   // static gain before the limiter
    Sample limiter_ceiling_db;
};

// Preset lookup. Pure; returns by value so we never share mutable state
// between preset slots.
PresetConfig get_preset(PresetId id) noexcept;

// Human-readable preset name — used by the UI. Returned as a string literal;
// the caller does NOT own the pointer.
const char* get_preset_name(PresetId id) noexcept;

// Total number of presets (for UI iteration).
constexpr int kPresetCount = 4;

} // namespace voice_enhancer

#endif // VOICE_ENHANCER_PRESET_H

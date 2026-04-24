#include "voice_enhancer/Preset.h"

namespace voice_enhancer {

// -----------------------------------------------------------------------------
// Preset definitions.
//
// These values were tuned by listening tests against a range of voices and
// common built-in microphones. Treat as "educated starting points" — open
// issues with audio samples before changing numbers, not opinions.
//
// Reading conventions:
//   * Negative thresholds are in dBFS. -18 means "start compressing when
//     the signal exceeds -18 dBFS".
//   * EQ gains of 0 mean "this band is flat" — the biquad still runs but
//     contributes no audible change.
// -----------------------------------------------------------------------------

namespace {

using dsp::ParametricEQ;

constexpr PresetConfig kNatural = {
    /* hpf_cutoff_hz              */ 80.0f,
    /* comp_threshold_db          */ -18.0f,
    /* comp_ratio                 */ 2.5f,
    /* comp_knee_db               */ 6.0f,
    /* comp_attack_ms             */ 10.0f,
    /* comp_release_ms            */ 120.0f,
    /* eq_bands                   */ {
        /* low shelf   */ { 180.0f,  0.7f,  0.0f },
        /* mud cut     */ { 320.0f,  1.4f, -1.5f },
        /* presence    */ { 4000.0f, 0.8f,  1.5f },
        /* high shelf  */ { 10000.0f, 0.7f,  1.0f },
    },
    /* deesser_crossover_hz       */ 6000.0f,
    /* deesser_threshold_db       */ -24.0f,
    /* deesser_ratio              */ 3.0f,
    /* deesser_max_reduction_db   */ 8.0f,
    /* output_gain_db             */ 0.0f,
    /* limiter_ceiling_db         */ -1.0f,
};

constexpr PresetConfig kBroadcast = {
    /* hpf_cutoff_hz              */ 100.0f,
    /* comp_threshold_db          */ -22.0f,
    /* comp_ratio                 */ 4.0f,
    /* comp_knee_db               */ 8.0f,
    /* comp_attack_ms             */ 5.0f,
    /* comp_release_ms            */ 80.0f,
    /* eq_bands                   */ {
        /* low shelf   */ { 160.0f,  0.7f,  2.0f },
        /* mud cut     */ { 280.0f,  1.5f, -2.5f },
        /* presence    */ { 3500.0f, 0.9f,  3.0f },
        /* high shelf  */ { 11000.0f, 0.7f,  2.0f },
    },
    /* deesser_crossover_hz       */ 5500.0f,
    /* deesser_threshold_db       */ -26.0f,
    /* deesser_ratio              */ 4.0f,
    /* deesser_max_reduction_db   */ 10.0f,
    /* output_gain_db             */ 2.0f,
    /* limiter_ceiling_db         */ -1.0f,
};

constexpr PresetConfig kClarity = {
    /* hpf_cutoff_hz              */ 90.0f,
    /* comp_threshold_db          */ -20.0f,
    /* comp_ratio                 */ 3.5f,
    /* comp_knee_db               */ 6.0f,
    /* comp_attack_ms             */ 8.0f,
    /* comp_release_ms            */ 100.0f,
    /* eq_bands                   */ {
        /* low shelf   */ { 200.0f,  0.7f,  0.0f },
        /* mud cut     */ { 350.0f,  1.6f, -3.0f },
        /* presence    */ { 4500.0f, 1.0f,  4.0f },
        /* high shelf  */ { 12000.0f, 0.7f,  1.5f },
    },
    /* deesser_crossover_hz       */ 6500.0f,
    /* deesser_threshold_db       */ -24.0f,
    /* deesser_ratio              */ 3.5f,
    /* deesser_max_reduction_db   */ 9.0f,
    /* output_gain_db             */ 3.0f,
    /* limiter_ceiling_db         */ -1.0f,
};

constexpr PresetConfig kWarm = {
    /* hpf_cutoff_hz              */ 75.0f,
    /* comp_threshold_db          */ -18.0f,
    /* comp_ratio                 */ 2.5f,
    /* comp_knee_db               */ 8.0f,
    /* comp_attack_ms             */ 15.0f,
    /* comp_release_ms            */ 150.0f,
    /* eq_bands                   */ {
        /* low shelf   */ { 200.0f,  0.7f,  3.0f },
        /* mud cut     */ { 350.0f,  1.2f, -1.0f },
        /* presence    */ { 3000.0f, 0.8f,  1.0f },
        /* high shelf  */ { 9000.0f, 0.7f, -1.5f },
    },
    /* deesser_crossover_hz       */ 6000.0f,
    /* deesser_threshold_db       */ -26.0f,
    /* deesser_ratio              */ 3.0f,
    /* deesser_max_reduction_db   */ 6.0f,
    /* output_gain_db             */ 0.0f,
    /* limiter_ceiling_db         */ -1.0f,
};

} // anonymous namespace

PresetConfig get_preset(PresetId id) noexcept {
    switch (id) {
        case PresetId::Natural:   return kNatural;
        case PresetId::Broadcast: return kBroadcast;
        case PresetId::Clarity:   return kClarity;
        case PresetId::Warm:      return kWarm;
    }
    return kNatural;
}

const char* get_preset_name(PresetId id) noexcept {
    switch (id) {
        case PresetId::Natural:   return "Natural";
        case PresetId::Broadcast: return "Broadcast";
        case PresetId::Clarity:   return "Clarity";
        case PresetId::Warm:      return "Warm";
    }
    return "Unknown";
}

} // namespace voice_enhancer

#ifndef VOICE_ENHANCER_DSP_COMPRESSOR_H
#define VOICE_ENHANCER_DSP_COMPRESSOR_H

#include "voice_enhancer/Types.h"

namespace voice_enhancer::dsp {

// A feed-forward peak compressor with soft knee, suitable for voice.
//
// Design choices:
//  * Peak detector (not RMS). RMS is more "musical" for drums or bass, but for
//    voice with a steep HPF already applied, peak is simpler and transient
//    behavior is easier to reason about.
//  * Log-domain envelope. Attack/release are applied to the dB signal, which
//    gives perceptually smoother gain reduction than linear-domain envelopes.
//  * Soft knee via 2nd-order interpolation across ±knee_db around the threshold.
//
// Parameters roughly target "spoken voice":
//   threshold: -18 dB
//   ratio:     3:1
//   knee:      6 dB
//   attack:    5 ms
//   release:   80 ms
//   makeup:    auto (computed from threshold+ratio so average level is preserved)
class Compressor {
public:
    Compressor() noexcept;

    // Set sample rate and reset envelope. Not RT-safe.
    void prepare(SampleRate sr) noexcept;

    // Clear internal envelope. RT-safe.
    void reset() noexcept;

    // Parameter setters. Safe to call from the UI thread while process_block
    // runs on audio thread — writes are to individual Sample fields which are
    // atomic on all our target architectures (aligned 32-bit). Callers should
    // avoid changing multiple parameters simultaneously expecting consistency.
    void set_threshold_db(Sample db) noexcept;
    void set_ratio       (Sample ratio) noexcept;
    void set_knee_db     (Sample db) noexcept;
    void set_attack_ms   (Sample ms) noexcept;
    void set_release_ms  (Sample ms) noexcept;
    void set_makeup_db   (Sample db) noexcept;

    // If true, makeup gain is set automatically to keep average output level
    // close to the input. Overrides set_makeup_db when enabled.
    void set_auto_makeup(bool enabled) noexcept;

    // Last computed gain reduction in dB (for meters). Thread-safe read.
    Sample get_gain_reduction_db() const noexcept { return m_last_gr_db; }

    // In-place block processing. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    // Compute per-sample gain reduction from input level in dB. RT-safe.
    Sample compute_gain_db(Sample level_db) const noexcept;

    // Recompute attack/release coefficients from ms values. Called when
    // attack/release setters are invoked.
    void recompute_time_coefficients() noexcept;

    SampleRate m_sample_rate;

    // Parameters.
    Sample m_threshold_db;
    Sample m_ratio;
    Sample m_knee_db;
    Sample m_attack_ms;
    Sample m_release_ms;
    Sample m_makeup_db;
    bool   m_auto_makeup;

    // Derived / state.
    Sample m_attack_coeff;   // one-pole coefficient for attack
    Sample m_release_coeff;  // one-pole coefficient for release
    Sample m_envelope_db;    // log-domain envelope state
    Sample m_last_gr_db;     // meter feedback
};

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_COMPRESSOR_H

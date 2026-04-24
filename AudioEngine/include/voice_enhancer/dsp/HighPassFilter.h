#ifndef VOICE_ENHANCER_DSP_HIGH_PASS_FILTER_H
#define VOICE_ENHANCER_DSP_HIGH_PASS_FILTER_H

#include "voice_enhancer/Types.h"
#include "voice_enhancer/dsp/Biquad.h"

namespace voice_enhancer::dsp {

// A steep high-pass filter used to remove rumble, HVAC, handling noise, and
// mic-stand thumps before anything else in the chain.
//
// Two cascaded biquads give a 24 dB/octave slope, which is the sweet spot
// for voice — steep enough to kill rumble without audible pre-ringing
// artifacts. A single biquad (12 dB/oct) is too gentle; four cascaded
// (48 dB/oct) adds phase smear to the low-mid vocal range.
class HighPassFilter {
public:
    HighPassFilter() noexcept;

    // Configure sample rate and reset state. Not RT-safe (may touch
    // coefficients); call during prepare, not during processing.
    void prepare(SampleRate sr) noexcept;

    // Clear state without changing parameters. RT-safe.
    void reset() noexcept;

    // Set cutoff frequency in Hz. Typical voice range: 60–120 Hz.
    // Not RT-safe — recomputes biquad coefficients. If you need per-buffer
    // modulation, introduce parameter smoothing here.
    void set_cutoff(Sample freq_hz) noexcept;

    // In-place block processing. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    void update_coefficients() noexcept;

    SampleRate m_sample_rate;
    Sample     m_cutoff_hz;

    // Two cascaded biquads. Butterworth Q for each stage of a 4th-order
    // cascaded HPF: 0.54 and 1.31 (see Cookbook / any DSP text).
    static constexpr Sample kStage1Q = 0.54f;
    static constexpr Sample kStage2Q = 1.31f;

    Biquad m_stage1;
    Biquad m_stage2;
};

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_HIGH_PASS_FILTER_H

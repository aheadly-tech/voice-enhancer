#ifndef VOICE_ENHANCER_DSP_BIQUAD_H
#define VOICE_ENHANCER_DSP_BIQUAD_H

#include "voice_enhancer/Types.h"

namespace voice_enhancer::dsp {

// Transposed Direct Form II biquad.
//
// This is the fundamental DSP building block used by every filter in the
// project (HPF, EQ bands, de-esser sidechain, etc.). TDF-II is chosen over
// DF-I because it has better numerical behavior when coefficients change
// continuously — important for parameter smoothing.
//
// Coefficients are in "normalized" form where a0 has already been divided out:
//   y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
//
// Not thread-safe. Each stage is owned by one thread.
class Biquad {
public:
    Biquad() noexcept;

    // Clear internal state. RT-safe.
    void reset() noexcept;

    // Set coefficients directly. RT-safe (plain memcpy of 5 floats).
    // Prefer using the make_* factory functions below for readability.
    void set_coefficients(Sample b0, Sample b1, Sample b2,
                          Sample a1, Sample a2) noexcept;

    // Process one sample. RT-safe, noexcept, trivially inlinable.
    inline Sample process_sample(Sample x) noexcept {
        const Sample y = m_b0 * x + m_z1;
        m_z1 = m_b1 * x - m_a1 * y + m_z2;
        m_z2 = m_b2 * x - m_a2 * y;
        return y;
    }

    // Process a block in-place. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    // Coefficients (a0 == 1 implicit).
    Sample m_b0, m_b1, m_b2;
    Sample m_a1, m_a2;

    // State (delay line).
    Sample m_z1, m_z2;
};

// Coefficient factory functions. These are called from parameter setters, NOT
// from the audio thread. They compute coefficients and hand them to set_*.
// Formulas from Robert Bristow-Johnson's "Cookbook formulae for audio EQ
// biquad filter coefficients".

struct BiquadCoeffs {
    Sample b0, b1, b2, a1, a2;
};

BiquadCoeffs make_highpass(SampleRate sr, Sample freq_hz, Sample q) noexcept;
BiquadCoeffs make_lowpass (SampleRate sr, Sample freq_hz, Sample q) noexcept;
BiquadCoeffs make_peaking (SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept;
BiquadCoeffs make_low_shelf (SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept;
BiquadCoeffs make_high_shelf(SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept;

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_BIQUAD_H

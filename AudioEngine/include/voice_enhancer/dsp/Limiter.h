#ifndef VOICE_ENHANCER_DSP_LIMITER_H
#define VOICE_ENHANCER_DSP_LIMITER_H

#include "voice_enhancer/Types.h"

#include <array>

namespace voice_enhancer::dsp {

// A final-stage brickwall-ish limiter. Prevents clipping on output regardless
// of what earlier stages did.
//
// This is a *simple* lookahead limiter, not a transparent mastering limiter.
// Lookahead is fixed at 2 ms which is enough to catch transients without
// adding audible latency.
//
// The lookahead buffer is a power-of-two ring buffer sized to handle 2 ms at
// 96 kHz with headroom (192 samples → next power of 2 is 256). This lets us
// mask the index with a bitwise AND rather than a modulo.
class Limiter {
public:
    static constexpr FrameCount kMaxLookaheadSamples = 256;  // ~2.6 ms at 96 kHz

    Limiter() noexcept;

    // Set sample rate and rebuild state. Not RT-safe.
    void prepare(SampleRate sr) noexcept;

    // Clear the lookahead buffer and envelope. RT-safe.
    void reset() noexcept;

    // Ceiling in dB. Typical: -1.0 dB (true-peak-safe margin).
    void set_ceiling_db(Sample db) noexcept;

    // Release time after a peak. Typical: 50 ms.
    void set_release_ms(Sample ms) noexcept;

    // In-place processing. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    SampleRate m_sample_rate;
    Sample m_ceiling_linear;
    Sample m_release_coeff;

    // Ring buffer for delayed signal.
    std::array<Sample, kMaxLookaheadSamples> m_delay_line;
    FrameCount m_write_index;
    FrameCount m_lookahead_samples;

    // Envelope (the gain we're currently applying; ≤ 1.0).
    Sample m_gain;
};

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_LIMITER_H

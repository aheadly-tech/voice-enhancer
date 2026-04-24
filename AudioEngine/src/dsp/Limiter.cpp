#include "voice_enhancer/dsp/Limiter.h"

#include <cmath>
#include <algorithm>

namespace voice_enhancer::dsp {

namespace {
constexpr Sample kLookaheadMs = 2.0f;
} // namespace

Limiter::Limiter() noexcept
    : m_sample_rate(48000.0)
    , m_ceiling_linear(db_to_linear(-1.0f))
    , m_release_coeff(0.0f)
    , m_write_index(0)
    , m_lookahead_samples(0)
    , m_gain(1.0f)
{
    m_delay_line.fill(0.0f);
}

void Limiter::prepare(SampleRate sr) noexcept {
    m_sample_rate = sr;

    // Lookahead length in samples, clamped to buffer capacity.
    const FrameCount desired =
        static_cast<FrameCount>(std::round(0.001 * static_cast<double>(kLookaheadMs) * sr));
    m_lookahead_samples = std::min(desired, kMaxLookaheadSamples - 1);

    set_release_ms(50.0f);
    reset();
}

void Limiter::reset() noexcept {
    m_delay_line.fill(0.0f);
    m_write_index = 0;
    m_gain = 1.0f;
}

void Limiter::set_ceiling_db(Sample db) noexcept {
    m_ceiling_linear = db_to_linear(db);
}

void Limiter::set_release_ms(Sample ms) noexcept {
    const Sample clamped = std::max(1.0f, ms);
    m_release_coeff =
        static_cast<Sample>(std::exp(-1.0 / (0.001 * static_cast<double>(clamped) * m_sample_rate)));
}

void Limiter::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    const Sample ceiling = m_ceiling_linear;
    const Sample release = m_release_coeff;
    const FrameCount look = m_lookahead_samples;
    // Ring buffer size (power of two) minus 1 gives the mask.
    constexpr FrameCount kMask = kMaxLookaheadSamples - 1;

    FrameCount w = m_write_index;
    Sample gain = m_gain;

    for (FrameCount i = 0; i < num_frames; ++i) {
        const Sample input = buffer[i];

        // Write current sample into the delay line.
        m_delay_line[static_cast<std::size_t>(w)] = input;

        // Compute the required gain for this incoming sample (not yet in the
        // output stream — it's `look` samples in the future from the output's
        // point of view). That is lookahead: we see the transient before we
        // emit anything from it.
        const Sample abs_x = std::fabs(input);
        Sample target_gain = 1.0f;
        if (abs_x > ceiling) {
            target_gain = ceiling / abs_x;
        }

        // Track minimum — instant attack, exponential release.
        if (target_gain < gain) {
            gain = target_gain;   // immediate pull-down
        } else {
            gain = release * gain + (1.0f - release) * 1.0f;
        }

        // Read delayed sample from `look` behind the write head and apply gain.
        const FrameCount r = (w - look) & kMask;
        buffer[i] = m_delay_line[static_cast<std::size_t>(r)] * gain;

        w = (w + 1) & kMask;
    }

    m_write_index = w;
    m_gain = gain;
}

} // namespace voice_enhancer::dsp

#include "voice_enhancer/dsp/HighPassFilter.h"

namespace voice_enhancer::dsp {

HighPassFilter::HighPassFilter() noexcept
    : m_sample_rate(48000.0)
    , m_cutoff_hz(80.0f)
{}

void HighPassFilter::prepare(SampleRate sr) noexcept {
    m_sample_rate = sr;
    update_coefficients();
    reset();
}

void HighPassFilter::reset() noexcept {
    m_stage1.reset();
    m_stage2.reset();
}

void HighPassFilter::set_cutoff(Sample freq_hz) noexcept {
    m_cutoff_hz = freq_hz;
    update_coefficients();
}

void HighPassFilter::update_coefficients() noexcept {
    const auto c1 = make_highpass(m_sample_rate, m_cutoff_hz, kStage1Q);
    const auto c2 = make_highpass(m_sample_rate, m_cutoff_hz, kStage2Q);
    m_stage1.set_coefficients(c1.b0, c1.b1, c1.b2, c1.a1, c1.a2);
    m_stage2.set_coefficients(c2.b0, c2.b1, c2.b2, c2.a1, c2.a2);
}

void HighPassFilter::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    m_stage1.process_block(buffer, num_frames);
    m_stage2.process_block(buffer, num_frames);
}

} // namespace voice_enhancer::dsp

#include "voice_enhancer/dsp/ParametricEQ.h"

namespace voice_enhancer::dsp {

ParametricEQ::ParametricEQ() noexcept
    : m_sample_rate(48000.0)
{
    // Sensible defaults — flat response.
    m_config[BandLowShelf]  = { 180.0f,  0.7f, 0.0f };
    m_config[BandMudCut]    = { 300.0f,  1.5f, 0.0f };
    m_config[BandPresence]  = { 3500.0f, 0.9f, 0.0f };
    m_config[BandHighShelf] = { 10000.0f, 0.7f, 0.0f };
}

void ParametricEQ::prepare(SampleRate sr) noexcept {
    m_sample_rate = sr;
    for (std::size_t b = 0; b < BandCount; ++b) {
        update_band_coefficients(static_cast<BandIndex>(b));
    }
    reset();
}

void ParametricEQ::reset() noexcept {
    for (auto& bq : m_biquads) {
        bq.reset();
    }
}

void ParametricEQ::set_band(BandIndex band, const BandConfig& cfg) noexcept {
    m_config[band] = cfg;
    update_band_coefficients(band);
}

void ParametricEQ::update_band_coefficients(BandIndex band) noexcept {
    const BandConfig& c = m_config[band];
    BiquadCoeffs coeffs;
    switch (band) {
        case BandLowShelf:
            coeffs = make_low_shelf(m_sample_rate, c.frequency_hz, c.q, c.gain_db);
            break;
        case BandHighShelf:
            coeffs = make_high_shelf(m_sample_rate, c.frequency_hz, c.q, c.gain_db);
            break;
        case BandMudCut:
        case BandPresence:
        default:
            coeffs = make_peaking(m_sample_rate, c.frequency_hz, c.q, c.gain_db);
            break;
    }
    m_biquads[band].set_coefficients(coeffs.b0, coeffs.b1, coeffs.b2,
                                     coeffs.a1, coeffs.a2);
}

void ParametricEQ::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    for (auto& bq : m_biquads) {
        bq.process_block(buffer, num_frames);
    }
}

} // namespace voice_enhancer::dsp

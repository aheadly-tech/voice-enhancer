#include "voice_enhancer/dsp/Biquad.h"

#include <cmath>

namespace voice_enhancer::dsp {

Biquad::Biquad() noexcept
    : m_b0(1.0f), m_b1(0.0f), m_b2(0.0f)
    , m_a1(0.0f), m_a2(0.0f)
    , m_z1(0.0f), m_z2(0.0f)
{}

void Biquad::reset() noexcept {
    m_z1 = 0.0f;
    m_z2 = 0.0f;
}

void Biquad::set_coefficients(Sample b0, Sample b1, Sample b2,
                              Sample a1, Sample a2) noexcept {
    m_b0 = b0;
    m_b1 = b1;
    m_b2 = b2;
    m_a1 = a1;
    m_a2 = a2;
}

void Biquad::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    // Intentionally a plain loop — the compiler inlines process_sample
    // and auto-vectorizes where possible. Measured faster than manual SIMD
    // for typical block sizes (64–512).
    for (FrameCount i = 0; i < num_frames; ++i) {
        buffer[i] = process_sample(buffer[i]);
    }
}

// -----------------------------------------------------------------------------
// Coefficient factories — RBJ cookbook.
// -----------------------------------------------------------------------------
//
// These are intentionally verbose rather than clever. The math runs off the
// audio thread so clarity beats brevity. The cookbook notation (w0, alpha, A)
// is preserved so the code can be read alongside the reference.

namespace {

struct Intermediate {
    double w0, cos_w0, sin_w0, alpha;
};

inline Intermediate compute_intermediate(SampleRate sr, Sample freq_hz, Sample q) noexcept {
    Intermediate i;
    i.w0 = 2.0 * M_PI * static_cast<double>(freq_hz) / sr;
    i.cos_w0 = std::cos(i.w0);
    i.sin_w0 = std::sin(i.w0);
    i.alpha = i.sin_w0 / (2.0 * static_cast<double>(q));
    return i;
}

inline BiquadCoeffs normalize(double b0, double b1, double b2,
                              double a0, double a1, double a2) noexcept {
    BiquadCoeffs c;
    c.b0 = static_cast<Sample>(b0 / a0);
    c.b1 = static_cast<Sample>(b1 / a0);
    c.b2 = static_cast<Sample>(b2 / a0);
    c.a1 = static_cast<Sample>(a1 / a0);
    c.a2 = static_cast<Sample>(a2 / a0);
    return c;
}

} // anonymous namespace

BiquadCoeffs make_highpass(SampleRate sr, Sample freq_hz, Sample q) noexcept {
    const auto i = compute_intermediate(sr, freq_hz, q);
    const double b0 =  (1.0 + i.cos_w0) / 2.0;
    const double b1 = -(1.0 + i.cos_w0);
    const double b2 =  (1.0 + i.cos_w0) / 2.0;
    const double a0 =   1.0 + i.alpha;
    const double a1 =  -2.0 * i.cos_w0;
    const double a2 =   1.0 - i.alpha;
    return normalize(b0, b1, b2, a0, a1, a2);
}

BiquadCoeffs make_lowpass(SampleRate sr, Sample freq_hz, Sample q) noexcept {
    const auto i = compute_intermediate(sr, freq_hz, q);
    const double b0 = (1.0 - i.cos_w0) / 2.0;
    const double b1 =  1.0 - i.cos_w0;
    const double b2 = (1.0 - i.cos_w0) / 2.0;
    const double a0 =  1.0 + i.alpha;
    const double a1 = -2.0 * i.cos_w0;
    const double a2 =  1.0 - i.alpha;
    return normalize(b0, b1, b2, a0, a1, a2);
}

BiquadCoeffs make_peaking(SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept {
    const auto i = compute_intermediate(sr, freq_hz, q);
    const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
    const double b0 =  1.0 + i.alpha * A;
    const double b1 = -2.0 * i.cos_w0;
    const double b2 =  1.0 - i.alpha * A;
    const double a0 =  1.0 + i.alpha / A;
    const double a1 = -2.0 * i.cos_w0;
    const double a2 =  1.0 - i.alpha / A;
    return normalize(b0, b1, b2, a0, a1, a2);
}

BiquadCoeffs make_low_shelf(SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept {
    const auto i = compute_intermediate(sr, freq_hz, q);
    const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
    const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * i.alpha;
    const double b0 =    A * ((A + 1.0) - (A - 1.0) * i.cos_w0 + two_sqrt_A_alpha);
    const double b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * i.cos_w0);
    const double b2 =    A * ((A + 1.0) - (A - 1.0) * i.cos_w0 - two_sqrt_A_alpha);
    const double a0 =        (A + 1.0) + (A - 1.0) * i.cos_w0 + two_sqrt_A_alpha;
    const double a1 =   -2.0 * ((A - 1.0) + (A + 1.0) * i.cos_w0);
    const double a2 =        (A + 1.0) + (A - 1.0) * i.cos_w0 - two_sqrt_A_alpha;
    return normalize(b0, b1, b2, a0, a1, a2);
}

BiquadCoeffs make_high_shelf(SampleRate sr, Sample freq_hz, Sample q, Sample gain_db) noexcept {
    const auto i = compute_intermediate(sr, freq_hz, q);
    const double A = std::pow(10.0, static_cast<double>(gain_db) / 40.0);
    const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * i.alpha;
    const double b0 =     A * ((A + 1.0) + (A - 1.0) * i.cos_w0 + two_sqrt_A_alpha);
    const double b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * i.cos_w0);
    const double b2 =     A * ((A + 1.0) + (A - 1.0) * i.cos_w0 - two_sqrt_A_alpha);
    const double a0 =         (A + 1.0) - (A - 1.0) * i.cos_w0 + two_sqrt_A_alpha;
    const double a1 =    2.0 * ((A - 1.0) - (A + 1.0) * i.cos_w0);
    const double a2 =         (A + 1.0) - (A - 1.0) * i.cos_w0 - two_sqrt_A_alpha;
    return normalize(b0, b1, b2, a0, a1, a2);
}

} // namespace voice_enhancer::dsp

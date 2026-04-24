#include "voice_enhancer/dsp/Compressor.h"

#include <cmath>
#include <algorithm>

namespace voice_enhancer::dsp {

Compressor::Compressor() noexcept
    : m_sample_rate(48000.0)
    , m_threshold_db(-18.0f)
    , m_ratio(3.0f)
    , m_knee_db(6.0f)
    , m_attack_ms(5.0f)
    , m_release_ms(80.0f)
    , m_makeup_db(0.0f)
    , m_auto_makeup(true)
    , m_attack_coeff(0.0f)
    , m_release_coeff(0.0f)
    , m_envelope_db(kMinDb)
    , m_last_gr_db(0.0f)
{}

void Compressor::prepare(SampleRate sr) noexcept {
    m_sample_rate = sr;
    recompute_time_coefficients();
    reset();
}

void Compressor::reset() noexcept {
    m_envelope_db = kMinDb;
    m_last_gr_db = 0.0f;
}

void Compressor::set_threshold_db(Sample db) noexcept { m_threshold_db = db; }
void Compressor::set_ratio       (Sample ratio) noexcept { m_ratio = std::max(1.0f, ratio); }
void Compressor::set_knee_db     (Sample db) noexcept { m_knee_db = std::max(0.0f, db); }
void Compressor::set_makeup_db   (Sample db) noexcept { m_makeup_db = db; }
void Compressor::set_auto_makeup (bool enabled) noexcept { m_auto_makeup = enabled; }

void Compressor::set_attack_ms(Sample ms) noexcept {
    m_attack_ms = std::max(0.1f, ms);
    recompute_time_coefficients();
}

void Compressor::set_release_ms(Sample ms) noexcept {
    m_release_ms = std::max(1.0f, ms);
    recompute_time_coefficients();
}

void Compressor::recompute_time_coefficients() noexcept {
    // Standard one-pole: coeff = exp(-1 / (time_seconds * sample_rate)).
    // Giving ~63% of the step response in `time_ms` ms.
    const double fs = m_sample_rate;
    m_attack_coeff  = static_cast<Sample>(std::exp(-1.0 / (0.001 * static_cast<double>(m_attack_ms ) * fs)));
    m_release_coeff = static_cast<Sample>(std::exp(-1.0 / (0.001 * static_cast<double>(m_release_ms) * fs)));
}

Sample Compressor::compute_gain_db(Sample level_db) const noexcept {
    // Soft-knee static curve.
    const Sample t = m_threshold_db;
    const Sample k = m_knee_db;
    const Sample half_knee = k * 0.5f;

    // Below the knee: no compression.
    if (level_db <= t - half_knee) {
        return 0.0f;
    }

    // Above the knee: full-ratio compression.
    if (level_db >= t + half_knee) {
        const Sample over = level_db - t;
        return -(over - over / m_ratio);
    }

    // Inside the knee: quadratic interpolation between "no compression"
    // and "full compression" (standard smooth-knee formulation).
    const Sample x = level_db - t + half_knee;   // 0..k
    const Sample a = (1.0f / m_ratio - 1.0f) / (2.0f * k);
    return a * x * x;
}

void Compressor::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    // Read parameters once per block. Avoids re-reading from memory per sample
    // and gives us a stable view even if setters race.
    const Sample attack  = m_attack_coeff;
    const Sample release = m_release_coeff;
    const Sample makeup  = m_auto_makeup
        ? -compute_gain_db(0.0f) * 0.5f   // Approximate: half the GR at 0 dBFS.
        : m_makeup_db;
    const Sample makeup_linear = db_to_linear(makeup);

    Sample envelope = m_envelope_db;
    Sample max_gr = 0.0f;

    for (FrameCount i = 0; i < num_frames; ++i) {
        const Sample x = buffer[i];
        const Sample abs_x = std::fabs(x);

        // Peak detector in dB, with -inf floor. Uses fast_linear_to_db to
        // avoid per-sample std::log10 (IEEE 754 bit trick, ~0.1 dB accuracy).
        const Sample x_db = fast_linear_to_db(abs_x);

        // Log-domain ballistics: attack when input is louder than envelope,
        // release when quieter. Standard one-pole on each side.
        if (x_db > envelope) {
            envelope = attack  * envelope + (1.0f - attack ) * x_db;
        } else {
            envelope = release * envelope + (1.0f - release) * x_db;
        }

        const Sample gain_db = compute_gain_db(envelope);
        if (gain_db < max_gr) max_gr = gain_db;   // most negative = most GR

        const Sample gain_linear = fast_db_to_linear(gain_db) * makeup_linear;
        buffer[i] = x * gain_linear;
    }

    m_envelope_db = envelope;
    m_last_gr_db = max_gr;
}

} // namespace voice_enhancer::dsp

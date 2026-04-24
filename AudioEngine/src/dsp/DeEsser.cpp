#include "voice_enhancer/dsp/DeEsser.h"

#include <cmath>
#include <algorithm>

namespace voice_enhancer::dsp {

namespace {
// De-esser ballistics are fast; sibilance is short. These aren't tunable
// from the outside in v1 because the presets don't need to vary them.
constexpr Sample kAttackMs  = 1.0f;
constexpr Sample kReleaseMs = 30.0f;
} // namespace

DeEsser::DeEsser() noexcept
    : m_sample_rate(48000.0)
    , m_crossover_hz(5500.0f)
    , m_threshold_db(-28.0f)
    , m_ratio(4.0f)
    , m_max_reduction_db(10.0f)
    , m_envelope_db(kMinDb)
    , m_attack_coeff(0.0f)
    , m_release_coeff(0.0f)
    , m_last_gr_db(0.0f)
{}

void DeEsser::prepare(SampleRate sr) noexcept {
    m_sample_rate = sr;
    const double fs = sr;
    m_attack_coeff  = static_cast<Sample>(std::exp(-1.0 / (0.001 * static_cast<double>(kAttackMs ) * fs)));
    m_release_coeff = static_cast<Sample>(std::exp(-1.0 / (0.001 * static_cast<double>(kReleaseMs) * fs)));
    update_filters();
    reset();
}

void DeEsser::reset() noexcept {
    m_hpf1.reset();
    m_hpf2.reset();
    m_envelope_db = kMinDb;
    m_last_gr_db = 0.0f;
}

void DeEsser::set_crossover_hz(Sample hz) noexcept {
    m_crossover_hz = hz;
    update_filters();
}

void DeEsser::set_threshold_db  (Sample db)    noexcept { m_threshold_db = db; }
void DeEsser::set_ratio         (Sample ratio) noexcept { m_ratio = std::max(1.0f, ratio); }
void DeEsser::set_max_reduction_db(Sample db)  noexcept { m_max_reduction_db = std::max(0.0f, db); }

void DeEsser::update_filters() noexcept {
    const auto c1 = make_highpass(m_sample_rate, m_crossover_hz, 0.54f);
    const auto c2 = make_highpass(m_sample_rate, m_crossover_hz, 1.31f);
    m_hpf1.set_coefficients(c1.b0, c1.b1, c1.b2, c1.a1, c1.a2);
    m_hpf2.set_coefficients(c2.b0, c2.b1, c2.b2, c2.a1, c2.a2);
}

void DeEsser::process_block(Sample* buffer, FrameCount num_frames) noexcept {
    const Sample attack  = m_attack_coeff;
    const Sample release = m_release_coeff;
    const Sample threshold = m_threshold_db;
    const Sample ratio     = m_ratio;
    const Sample max_gr    = -m_max_reduction_db;

    Sample envelope = m_envelope_db;
    Sample worst_gr = 0.0f;

    for (FrameCount i = 0; i < num_frames; ++i) {
        const Sample input = buffer[i];

        // Split.
        Sample high = input;
        high = m_hpf1.process_sample(high);
        high = m_hpf2.process_sample(high);
        const Sample low = input - high;

        // Peak-detect the sibilance band in dB. Uses fast_linear_to_db to
        // avoid per-sample std::log10 (IEEE 754 bit trick, ~0.1 dB accuracy).
        const Sample abs_h = std::fabs(high);
        const Sample h_db = fast_linear_to_db(abs_h);

        if (h_db > envelope) {
            envelope = attack  * envelope + (1.0f - attack ) * h_db;
        } else {
            envelope = release * envelope + (1.0f - release) * h_db;
        }

        // Hard-knee gain computation above threshold.
        Sample gain_db = 0.0f;
        if (envelope > threshold) {
            const Sample over = envelope - threshold;
            gain_db = -(over - over / ratio);
        }
        if (gain_db < max_gr) gain_db = max_gr;
        if (gain_db < worst_gr) worst_gr = gain_db;

        const Sample gain_linear = fast_db_to_linear(gain_db);

        // Recombine: unaffected low band + compressed high band.
        buffer[i] = low + high * gain_linear;
    }

    m_envelope_db = envelope;
    m_last_gr_db = worst_gr;
}

} // namespace voice_enhancer::dsp

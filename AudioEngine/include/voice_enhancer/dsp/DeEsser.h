#ifndef VOICE_ENHANCER_DSP_DE_ESSER_H
#define VOICE_ENHANCER_DSP_DE_ESSER_H

#include "voice_enhancer/Types.h"
#include "voice_enhancer/dsp/Biquad.h"

namespace voice_enhancer::dsp {

// A split-band de-esser: detect sibilance in the 5–8 kHz band, compress
// only that band, sum back with the unaffected low/mid signal.
//
// Why split-band and not full-band with a high-Q EQ dip? A static EQ dip
// dulls all "s" sounds equally, including the ones that are fine. A
// compressor on a band-pass sidechain only pulls down *excessive* sibilance,
// preserving natural articulation.
//
// Implementation:
//   high_band = HPF(signal @ 5 kHz)        — what we compress
//   low_band  = signal - high_band         — what we leave alone
//   gain_db   = compressor.compute(peak(high_band))
//   output    = low_band + high_band * db_to_linear(gain_db)
class DeEsser {
public:
    DeEsser() noexcept;

    // Set sample rate and rebuild filter. Not RT-safe.
    void prepare(SampleRate sr) noexcept;

    // Clear state. RT-safe.
    void reset() noexcept;

    // Cross-over frequency between "body" and "sibilance". Typical: 5–7 kHz.
    void set_crossover_hz(Sample hz) noexcept;

    // Threshold for the sibilance-band compressor. Typical: -28 dB.
    void set_threshold_db(Sample db) noexcept;

    // Gain reduction ratio for the sibilance band. Typical: 4:1.
    void set_ratio(Sample ratio) noexcept;

    // Maximum allowed gain reduction in dB — a safety clamp so we never
    // completely annihilate the "s" (which would sound worse than leaving it).
    // Typical: 10 dB.
    void set_max_reduction_db(Sample db) noexcept;

    // Last gain reduction applied, for meters. Thread-safe read.
    Sample get_gain_reduction_db() const noexcept { return m_last_gr_db; }

    // In-place processing. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    void update_filters() noexcept;

    SampleRate m_sample_rate;
    Sample m_crossover_hz;
    Sample m_threshold_db;
    Sample m_ratio;
    Sample m_max_reduction_db;

    // Linkwitz-Riley-ish 4th-order split via two cascaded biquads for HPF.
    // LPF is derived as "input - HPF_output" (complementary).
    Biquad m_hpf1;
    Biquad m_hpf2;

    // Envelope follower on the sibilance band.
    Sample m_envelope_db;
    Sample m_attack_coeff;
    Sample m_release_coeff;

    Sample m_last_gr_db;
};

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_DE_ESSER_H

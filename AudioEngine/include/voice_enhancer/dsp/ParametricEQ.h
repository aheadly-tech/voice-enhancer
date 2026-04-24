#ifndef VOICE_ENHANCER_DSP_PARAMETRIC_EQ_H
#define VOICE_ENHANCER_DSP_PARAMETRIC_EQ_H

#include "voice_enhancer/Types.h"
#include "voice_enhancer/dsp/Biquad.h"

namespace voice_enhancer::dsp {

// A 4-band parametric EQ tuned for voice.
//
// Band layout (fixed for v1; presets tune the gains):
//   Band 0: low shelf       — body / warmth    (~180 Hz)
//   Band 1: peaking          — mud cut          (~300 Hz, narrow)
//   Band 2: peaking          — presence         (~3.5 kHz)
//   Band 3: high shelf       — air              (~10 kHz)
//
// More than 4 bands rarely adds audible benefit for voice and makes presets
// harder to reason about. If we find we need more, we extend the enum and
// bump the preset format version.
class ParametricEQ {
public:
    enum BandIndex : std::size_t {
        BandLowShelf  = 0,
        BandMudCut    = 1,
        BandPresence  = 2,
        BandHighShelf = 3,
        BandCount     = 4,
    };

    struct BandConfig {
        Sample frequency_hz;
        Sample q;
        Sample gain_db;
    };

    ParametricEQ() noexcept;

    // Set sample rate and rebuild coefficients. Not RT-safe.
    void prepare(SampleRate sr) noexcept;

    // Clear filter state. RT-safe.
    void reset() noexcept;

    // Update one band's configuration. Not RT-safe (recomputes coefficients).
    // Parameter smoothing is not implemented in v1 — preset changes apply
    // instantly but the engine's gain_smoother takes the sharp edge off.
    void set_band(BandIndex band, const BandConfig& cfg) noexcept;

    // In-place processing. RT-safe.
    void process_block(Sample* buffer, FrameCount num_frames) noexcept;

private:
    void update_band_coefficients(BandIndex band) noexcept;

    SampleRate m_sample_rate;
    BandConfig m_config[BandCount];
    Biquad     m_biquads[BandCount];
};

} // namespace voice_enhancer::dsp

#endif // VOICE_ENHANCER_DSP_PARAMETRIC_EQ_H

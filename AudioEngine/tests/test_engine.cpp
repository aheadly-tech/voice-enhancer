// Minimal test runner. We intentionally avoid a framework dependency here —
// this code is small and the assertions we need are trivial.
//
// Run: ./voice_enhancer_tests
// Exit code: 0 on pass, non-zero on first failure.

#include "voice_enhancer/Engine.h"
#include "voice_enhancer/Preset.h"
#include "voice_enhancer/dsp/Biquad.h"
#include "voice_enhancer/dsp/HighPassFilter.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

int g_failures = 0;
const char* g_current_test = "<none>";

#define EXPECT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "FAIL [%s] %s:%d: %s\n", \
                     g_current_test, __FILE__, __LINE__, #cond); \
        ++g_failures; \
    } \
} while (0)

#define EXPECT_NEAR(actual, expected, tol) do { \
    const double _a = static_cast<double>(actual); \
    const double _e = static_cast<double>(expected); \
    if (std::fabs(_a - _e) > (tol)) { \
        std::fprintf(stderr, "FAIL [%s] %s:%d: expected %g got %g (tol %g)\n", \
                     g_current_test, __FILE__, __LINE__, _e, _a, (tol)); \
        ++g_failures; \
    } \
} while (0)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

std::vector<float> make_sine(double freq_hz, double sr, int num_frames, float amp = 1.0f) {
    std::vector<float> out(static_cast<std::size_t>(num_frames));
    const double w = 2.0 * M_PI * freq_hz / sr;
    for (int i = 0; i < num_frames; ++i) {
        out[static_cast<std::size_t>(i)] = amp * static_cast<float>(std::sin(w * i));
    }
    return out;
}

float peak(const std::vector<float>& buf) {
    float p = 0.0f;
    for (float x : buf) {
        const float a = std::fabs(x);
        if (a > p) p = a;
    }
    return p;
}

float rms(const std::vector<float>& buf) {
    double s = 0.0;
    for (float x : buf) s += static_cast<double>(x) * static_cast<double>(x);
    return static_cast<float>(std::sqrt(s / static_cast<double>(buf.size())));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void test_biquad_defaults_passthrough() {
    g_current_test = "biquad_defaults_passthrough";
    voice_enhancer::dsp::Biquad bq;
    auto buf = make_sine(1000.0, 48000.0, 256, 0.5f);
    const auto before = peak(buf);
    bq.process_block(buf.data(), static_cast<int>(buf.size()));
    EXPECT_NEAR(peak(buf), before, 1e-6);
}

void test_hpf_attenuates_rumble() {
    g_current_test = "hpf_attenuates_rumble";
    voice_enhancer::dsp::HighPassFilter hpf;
    hpf.prepare(48000.0);
    hpf.set_cutoff(80.0f);

    // Settle transient before measuring RMS by running through a few blocks
    // of 30 Hz signal.
    auto buf = make_sine(30.0, 48000.0, 4800, 1.0f);
    hpf.process_block(buf.data(), static_cast<int>(buf.size()));

    // Discard the first half (transient region).
    std::vector<float> steady(buf.begin() + 2400, buf.end());
    // 30 Hz vs 80 Hz cutoff should be attenuated by significantly more than
    // -20 dB with a 24 dB/oct slope.
    EXPECT_TRUE(rms(steady) < 0.1f);
}

void test_hpf_passes_voice_range() {
    g_current_test = "hpf_passes_voice_range";
    voice_enhancer::dsp::HighPassFilter hpf;
    hpf.prepare(48000.0);
    hpf.set_cutoff(80.0f);

    auto buf = make_sine(1000.0, 48000.0, 4800, 0.5f);
    const float in_rms = rms(buf);
    hpf.process_block(buf.data(), static_cast<int>(buf.size()));
    std::vector<float> steady(buf.begin() + 2400, buf.end());
    // 1 kHz should come through essentially unchanged.
    EXPECT_TRUE(rms(steady) > in_rms * 0.9f);
}

void test_engine_no_nans_under_extreme_input() {
    g_current_test = "engine_no_nans_under_extreme_input";
    voice_enhancer::Engine engine;
    engine.prepare(48000.0, 512);

    for (int preset_idx = 0; preset_idx < voice_enhancer::kPresetCount; ++preset_idx) {
        engine.set_preset(static_cast<voice_enhancer::PresetId>(preset_idx));

        // Feed a hot 1 kHz sine at -3 dBFS for a full second.
        auto buf = make_sine(1000.0, 48000.0, 48000, 0.707f);
        for (int i = 0; i < 48000; i += 512) {
            const int n = std::min(512, 48000 - i);
            engine.process_block(buf.data() + i, n);
        }
        for (float x : buf) {
            EXPECT_TRUE(std::isfinite(x));
        }
    }
}

void test_engine_bypass_is_transparent() {
    g_current_test = "engine_bypass_is_transparent";
    voice_enhancer::Engine engine;
    engine.prepare(48000.0, 512);
    engine.set_bypass(true);

    auto input = make_sine(1000.0, 48000.0, 512, 0.25f);
    auto buf = input;
    engine.process_block(buf.data(), 512);
    for (std::size_t i = 0; i < buf.size(); ++i) {
        EXPECT_NEAR(buf[i], input[i], 1e-6);
    }
}

void test_engine_limiter_holds_ceiling() {
    g_current_test = "engine_limiter_holds_ceiling";
    voice_enhancer::Engine engine;
    engine.prepare(48000.0, 512);
    engine.set_preset(voice_enhancer::PresetId::Broadcast);
    engine.set_input_gain_db(24.0f);   // force hot input

    // 1 kHz at full scale + 24 dB of input gain. The limiter ceiling is -1 dB
    // (~0.891 linear). After settling, peaks must not exceed this.
    auto buf = make_sine(1000.0, 48000.0, 48000, 1.0f);
    for (int i = 0; i < 48000; i += 512) {
        const int n = std::min(512, 48000 - i);
        engine.process_block(buf.data() + i, n);
    }
    // Measure only the last 20000 samples (post-attack-settling).
    std::vector<float> tail(buf.end() - 20000, buf.end());
    EXPECT_TRUE(peak(tail) <= 0.92f);   // small margin above -1 dB
}

void test_preset_names_are_valid() {
    g_current_test = "preset_names_are_valid";
    for (int i = 0; i < voice_enhancer::kPresetCount; ++i) {
        const char* name = voice_enhancer::get_preset_name(
            static_cast<voice_enhancer::PresetId>(i));
        EXPECT_TRUE(name != nullptr);
        EXPECT_TRUE(name[0] != '\0');
    }
}

} // anonymous namespace

int main() {
    test_biquad_defaults_passthrough();
    test_hpf_attenuates_rumble();
    test_hpf_passes_voice_range();
    test_engine_no_nans_under_extreme_input();
    test_engine_bypass_is_transparent();
    test_engine_limiter_holds_ceiling();
    test_preset_names_are_valid();

    if (g_failures == 0) {
        std::printf("All tests passed.\n");
        return 0;
    }
    std::printf("%d failure(s).\n", g_failures);
    return 1;
}

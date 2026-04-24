#ifndef VOICE_ENHANCER_TYPES_H
#define VOICE_ENHANCER_TYPES_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cmath>

namespace voice_enhancer {

// Sample type. float32 is the Core Audio native format and gives us ~144 dB of
// dynamic range — ample for voice. We do not support float64 or int16.
using Sample = float;

// Sample rate in Hz (e.g. 48000.0). Double on purpose — coefficient math
// benefits from the extra precision even though samples are float32.
using SampleRate = double;

// Number of frames (mono sample count) in a buffer. Stays within int for
// the foreseeable future; Core Audio buffers are typically 64–2048 frames.
using FrameCount = std::int32_t;

// Convenience: dB <-> linear gain conversions. Inline, constexpr where possible.
// Using natural log form because standard library log10/pow are runtime-only.
// These are used off the audio thread during parameter changes.
constexpr Sample kMinDb = -96.0f;

inline Sample db_to_linear(Sample db) noexcept {
    // 10^(db/20). Expressed via exp for potential future constexpr-ability.
    // Not hot path — called on parameter updates, not per sample.
    return static_cast<Sample>(__builtin_exp(0.11512925464970228 * static_cast<double>(db)));
}

inline Sample linear_to_db(Sample linear) noexcept {
    if (linear <= 1e-9f) {
        return kMinDb;
    }
    return static_cast<Sample>(20.0 * __builtin_log10(static_cast<double>(linear)));
}

// ---------------------------------------------------------------------------
// Fast approximations for the audio hot path.
//
// These use IEEE 754 bit tricks to avoid transcendental function calls.
// Accuracy is ~0.1 dB which is imperceptible for gain-envelope purposes.
// ---------------------------------------------------------------------------

// Fast log2 via IEEE 754 float bit layout. The exponent field gives the
// integer part; a 2nd-order polynomial refines the mantissa fraction.
inline Sample fast_log2(Sample x) noexcept {
    union { float f; std::uint32_t i; } v = {x};
    auto e = static_cast<float>(static_cast<int>((v.i >> 23) & 0xFF) - 127);
    v.i = (v.i & 0x007FFFFFu) | 0x3F800000u;  // normalize mantissa to [1,2)
    // 2nd-order minimax polynomial for log2(m) on [1,2):
    e += -0.33582878f + v.f * (2.0249f - 0.6891f * v.f);
    return e;
}

// 20*log10(|x|) without calling std::log10. Uses the identity
// 20*log10(x) = 20/log2(10) * log2(x) ≈ 6.0206 * log2(x).
inline Sample fast_linear_to_db(Sample x) noexcept {
    if (x <= 1e-9f) return kMinDb;
    return 6.0206f * fast_log2(x);
}

// Fast 2^x via IEEE 754 bit trick with polynomial refinement.
inline Sample fast_exp2(Sample x) noexcept {
    x = std::max(x, -126.0f);
    float xi = std::floor(x);
    float xf = x - xi;
    union { std::uint32_t i; float f; } v;
    v.i = static_cast<std::uint32_t>(static_cast<int>(xi) + 127) << 23;
    // 2nd-order polynomial for 2^frac on [0,1):
    v.f *= 1.0f + xf * (0.6931472f + xf * 0.2402265f);
    return v.f;
}

// 10^(db/20) without calling exp/pow. Uses the identity
// 10^(db/20) = 2^(db / (20*log10(2))) = 2^(db * 0.16609640474).
inline Sample fast_db_to_linear(Sample db) noexcept {
    return fast_exp2(db * 0.16609640474f);
}

} // namespace voice_enhancer

#endif // VOICE_ENHANCER_TYPES_H

/*
 * Voice Enhancer — C ABI bridge.
 *
 * A stable, plain-C interface over the C++ Engine. Intended to be imported
 * directly by Swift (via a bridging header / module map) or by any other
 * language with a C FFI.
 *
 * Design rules:
 *   1. Pure C. No C++ types in signatures.
 *   2. Opaque handle (`ve_engine_t`) — callers never see the engine internals.
 *   3. All functions are noexcept. Failures are reported via return codes,
 *      not exceptions.
 *   4. No C++ exceptions escape this boundary; the .cpp file wraps calls in
 *      try/catch and swallows failures.
 *
 * Thread safety mirrors the C++ engine:
 *   * ve_engine_create / destroy / prepare  — caller's thread (not audio).
 *   * ve_engine_set_*                       — any thread.
 *   * ve_engine_process                     — audio thread only.
 *   * ve_engine_get_*                       — any thread (lock-free).
 */

#ifndef VOICE_ENHANCER_C_API_H
#define VOICE_ENHANCER_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* ---------------------------------------------------------------------------
 * Opaque handle
 * --------------------------------------------------------------------------- */

typedef struct ve_engine_s ve_engine_t;

/* ---------------------------------------------------------------------------
 * Preset identifiers — keep these in sync with C++ PresetId.
 * --------------------------------------------------------------------------- */

typedef enum ve_preset_e {
    VE_PRESET_NATURAL   = 0,
    VE_PRESET_BROADCAST = 1,
    VE_PRESET_CLARITY   = 2,
    VE_PRESET_WARM      = 3,
} ve_preset_t;

#define VE_PRESET_COUNT 4

/* ---------------------------------------------------------------------------
 * Return codes
 * --------------------------------------------------------------------------- */

typedef enum ve_status_e {
    VE_OK               = 0,
    VE_ERROR_INVALID    = -1,
    VE_ERROR_NOT_READY  = -2,
    VE_ERROR_INTERNAL   = -3,
} ve_status_t;

/* ---------------------------------------------------------------------------
 * Lifecycle
 * --------------------------------------------------------------------------- */

/* Create an engine instance. Returns NULL on allocation failure. */
ve_engine_t* ve_engine_create(void);

/* Destroy an engine instance. Safe to pass NULL. */
void ve_engine_destroy(ve_engine_t* engine);

/* Prepare the engine for processing. Must be called before ve_engine_process.
 * Allocates internal state; not real-time safe. */
ve_status_t ve_engine_prepare(ve_engine_t* engine,
                              double       sample_rate,
                              int32_t      max_block_size);

/* Clear all internal DSP state (filter memory, envelopes). RT-safe. */
void ve_engine_reset(ve_engine_t* engine);

/* ---------------------------------------------------------------------------
 * Parameter setters (thread-safe, callable from UI thread)
 * --------------------------------------------------------------------------- */

ve_status_t ve_engine_set_preset             (ve_engine_t* engine, ve_preset_t preset);
void        ve_engine_set_bypass             (ve_engine_t* engine, int32_t bypass /*0 or 1*/);
void        ve_engine_set_input_gain_db      (ve_engine_t* engine, float db);
void        ve_engine_set_output_gain_db     (ve_engine_t* engine, float db);
void        ve_engine_set_comp_threshold_db  (ve_engine_t* engine, float db);
void        ve_engine_set_deesser_threshold_db(ve_engine_t* engine, float db);

/* Human-readable name of a preset. Pointer is valid forever; do not free. */
const char* ve_preset_name(ve_preset_t preset);

/* ---------------------------------------------------------------------------
 * Meters (thread-safe, callable from UI thread)
 * --------------------------------------------------------------------------- */

float ve_engine_get_input_peak      (const ve_engine_t* engine);
float ve_engine_get_output_peak     (const ve_engine_t* engine);
float ve_engine_get_compressor_gr_db(const ve_engine_t* engine);
float ve_engine_get_deesser_gr_db   (const ve_engine_t* engine);

/* ---------------------------------------------------------------------------
 * Audio processing (audio thread only)
 * --------------------------------------------------------------------------- */

/* Process one mono block of float samples in place.
 *
 *   engine      — must be non-NULL and prepared.
 *   buffer      — num_frames float32 samples; written in place.
 *   num_frames  — must be <= max_block_size used in ve_engine_prepare.
 *
 * Returns 0 on success, a negative ve_status_t on failure. If this returns
 * non-zero, the buffer contents are undefined and the caller should output
 * silence for that block.
 */
ve_status_t ve_engine_process(ve_engine_t* engine,
                              float*       buffer,
                              int32_t      num_frames);

/* ---------------------------------------------------------------------------
 * Shared-memory ring buffer (app → driver).
 *
 * The app opens the ring at startup, writes processed audio into it from
 * the audio thread, and closes it at shutdown. The HAL driver attaches to
 * the same segment and pulls audio out on its I/O cycle.
 *
 * The implementation lives in shared/RingBuffer.h — this C ABI is a thin
 * shim so the Swift side can use it without opening the C++17 can of worms.
 *
 * All functions are noexcept (never throw; never call setjmp; never
 * invoke Swift runtime hooks).
 * --------------------------------------------------------------------------- */

typedef struct ve_ring_s ve_ring_t;

/* Open or create the shared-memory ring. Returns NULL if the OS shared-
 * memory API is unavailable or permission is denied. NOT RT-safe. */
ve_ring_t* ve_ring_open(void);

/* Release the mapping. Safe to pass NULL. NOT RT-safe. */
void ve_ring_close(ve_ring_t* ring);

/* Remove the ring from the filesystem. Call on clean uninstall; leaving
 * stale segments is harmless but tidies up. NOT RT-safe. */
void ve_ring_unlink(void);

/* Publish `num_frames` of float32 mono samples to the ring.
 *
 * Overruns are handled by dropping the OLDEST audio, not the new. This
 * is the right trade-off for a voice path: stale audio is worse than a
 * small skip.
 *
 * RT-safe: no syscalls, no allocations, no locks. Safe to call from the
 * audio render thread.
 */
void ve_ring_write(ve_ring_t* ring, const float* samples, int32_t num_frames);

/* Diagnostics: how many frames of room is currently available for writes.
 * RT-safe. Useful for surfacing IPC health in the UI. */
int32_t ve_ring_writable(const ve_ring_t* ring);

/* Mark the producer-side generation counter so the consumer (driver) can
 * detect that the app has (re)started. Call once per StartIO. RT-safe. */
void ve_ring_bump_generation(ve_ring_t* ring);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* VOICE_ENHANCER_C_API_H */

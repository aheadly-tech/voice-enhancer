// Voice Enhancer — C ABI implementation.
//
// Thin wrapper over voice_enhancer::Engine. Two responsibilities only:
//   1. Translate C types (int32_t, ve_preset_t) to C++ types.
//   2. Enforce noexcept boundary: any exception inside the C++ engine must
//      not propagate out through the C ABI (undefined behavior).
//
// Nothing DSP-related lives here. If you find yourself adding DSP logic,
// you're modifying the wrong file.

#include "engine_c_api.h"
#include "voice_enhancer/Engine.h"
#include "voice_enhancer/Preset.h"

#include "../../shared/RingBuffer.h"

#include <new>

// Opaque handle — we simply alias it to our C++ type.
struct ve_engine_s {
    voice_enhancer::Engine engine;
};

namespace {

inline voice_enhancer::Engine& engine_ref(ve_engine_t* e) noexcept {
    return e->engine;
}

inline const voice_enhancer::Engine& engine_ref(const ve_engine_t* e) noexcept {
    return e->engine;
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

extern "C" ve_engine_t* ve_engine_create(void) {
    try {
        return new ve_engine_s();
    } catch (...) {
        return nullptr;
    }
}

extern "C" void ve_engine_destroy(ve_engine_t* engine) {
    delete engine;   // nullptr is fine for delete
}

extern "C" ve_status_t ve_engine_prepare(ve_engine_t* engine,
                                         double sample_rate,
                                         int32_t max_block_size) {
    if (engine == nullptr)         return VE_ERROR_INVALID;
    if (sample_rate <= 0.0)        return VE_ERROR_INVALID;
    if (max_block_size <= 0)       return VE_ERROR_INVALID;

    try {
        engine_ref(engine).prepare(sample_rate, max_block_size);
        return VE_OK;
    } catch (...) {
        return VE_ERROR_INTERNAL;
    }
}

extern "C" void ve_engine_reset(ve_engine_t* engine) {
    if (engine == nullptr) return;
    engine_ref(engine).reset();
}

// ---------------------------------------------------------------------------
// Parameter setters
// ---------------------------------------------------------------------------

extern "C" ve_status_t ve_engine_set_preset(ve_engine_t* engine, ve_preset_t preset) {
    if (engine == nullptr) return VE_ERROR_INVALID;
    if (preset < 0 || preset >= VE_PRESET_COUNT) return VE_ERROR_INVALID;

    engine_ref(engine).set_preset(static_cast<voice_enhancer::PresetId>(preset));
    return VE_OK;
}

extern "C" void ve_engine_set_bypass(ve_engine_t* engine, int32_t bypass) {
    if (engine == nullptr) return;
    engine_ref(engine).set_bypass(bypass != 0);
}

extern "C" void ve_engine_set_input_gain_db(ve_engine_t* engine, float db) {
    if (engine == nullptr) return;
    engine_ref(engine).set_input_gain_db(db);
}

extern "C" void ve_engine_set_output_gain_db(ve_engine_t* engine, float db) {
    if (engine == nullptr) return;
    engine_ref(engine).set_output_gain_db(db);
}

extern "C" void ve_engine_set_comp_threshold_db(ve_engine_t* engine, float db) {
    if (engine == nullptr) return;
    engine_ref(engine).set_comp_threshold_db(db);
}

extern "C" void ve_engine_set_deesser_threshold_db(ve_engine_t* engine, float db) {
    if (engine == nullptr) return;
    engine_ref(engine).set_deesser_threshold_db(db);
}

extern "C" const char* ve_preset_name(ve_preset_t preset) {
    return voice_enhancer::get_preset_name(static_cast<voice_enhancer::PresetId>(preset));
}

// ---------------------------------------------------------------------------
// Meters
// ---------------------------------------------------------------------------

extern "C" float ve_engine_get_input_peak(const ve_engine_t* engine) {
    if (engine == nullptr) return 0.0f;
    return engine_ref(engine).get_input_peak();
}

extern "C" float ve_engine_get_output_peak(const ve_engine_t* engine) {
    if (engine == nullptr) return 0.0f;
    return engine_ref(engine).get_output_peak();
}

extern "C" float ve_engine_get_compressor_gr_db(const ve_engine_t* engine) {
    if (engine == nullptr) return 0.0f;
    return engine_ref(engine).get_compressor_gr_db();
}

extern "C" float ve_engine_get_deesser_gr_db(const ve_engine_t* engine) {
    if (engine == nullptr) return 0.0f;
    return engine_ref(engine).get_deesser_gr_db();
}

// ---------------------------------------------------------------------------
// Processing
// ---------------------------------------------------------------------------

extern "C" ve_status_t ve_engine_process(ve_engine_t* engine,
                                         float* buffer,
                                         int32_t num_frames) {
    if (engine == nullptr) return VE_ERROR_INVALID;
    if (buffer == nullptr) return VE_ERROR_INVALID;
    if (num_frames <= 0)   return VE_OK;   // no-op on empty block

    // No try/catch here: process_block is noexcept by contract. If something
    // throws inside it, we have a much bigger problem than this return code.
    engine_ref(engine).process_block(buffer, num_frames);
    return VE_OK;
}

// ---------------------------------------------------------------------------
// Ring buffer (app → driver)
//
// The opaque handle wraps a RingBufferSegment pointer. One level of
// indirection keeps the C signature stable if we ever add bookkeeping
// (refcounts, lazy re-open, etc.) on the app side.
// ---------------------------------------------------------------------------

struct ve_ring_s {
    voice_enhancer::RingBufferSegment* seg;
};

extern "C" ve_ring_t* ve_ring_open(void) {
    auto* seg = voice_enhancer::RingBuffer::open_or_create();
    if (seg == nullptr) return nullptr;
    auto* ring = new (std::nothrow) ve_ring_s{seg};
    if (ring == nullptr) {
        voice_enhancer::RingBuffer::close_mapping(seg);
        return nullptr;
    }
    return ring;
}

extern "C" void ve_ring_close(ve_ring_t* ring) {
    if (ring == nullptr) return;
    voice_enhancer::RingBuffer::close_mapping(ring->seg);
    delete ring;
}

extern "C" void ve_ring_unlink(void) {
    voice_enhancer::RingBuffer::unlink_shm();
}

extern "C" void ve_ring_write(ve_ring_t* ring,
                              const float* samples,
                              int32_t num_frames) {
    if (ring == nullptr || ring->seg == nullptr) return;
    if (samples == nullptr || num_frames <= 0) return;
    voice_enhancer::RingBuffer::write(ring->seg, samples,
                                      static_cast<std::uint32_t>(num_frames));
}

extern "C" int32_t ve_ring_writable(const ve_ring_t* ring) {
    if (ring == nullptr || ring->seg == nullptr) return 0;
    return static_cast<int32_t>(
        voice_enhancer::RingBuffer::writable(ring->seg));
}

extern "C" void ve_ring_bump_generation(ve_ring_t* ring) {
    if (ring == nullptr || ring->seg == nullptr) return;
    voice_enhancer::RingBuffer::bump_writer_generation(ring->seg);
}

// Diagnostic helper — not exposed in the public C API header but kept for
// future debugging. Call from Swift via bridging header if needed.
#if 0
extern "C" int32_t ve_ring_diagnose(const char* log_path) {
    FILE* f = nullptr;
    if (log_path) f = fopen(log_path, "a");

    errno = 0;
    int fd = shm_open(voice_enhancer::kRingShmName, O_CREAT | O_RDWR, 0666);
    int open_errno = errno;

    if (f) {
        fprintf(f, "ve_ring_diagnose: shm_open(\"%s\", O_CREAT|O_RDWR, 0666) fd=%d errno=%d (%s)\n",
                voice_enhancer::kRingShmName, fd, open_errno, strerror(open_errno));
    }

    if (fd >= 0) {
        struct stat st;
        fstat(fd, &st);
        if (f) {
            fprintf(f, "  size=%lld uid=%d gid=%d mode=%o\n",
                    (long long)st.st_size, st.st_uid, st.st_gid, st.st_mode & 0777);
        }

        errno = 0;
        int tr = ftruncate(fd, static_cast<off_t>(sizeof(voice_enhancer::RingBufferSegment)));
        int trunc_errno = errno;
        if (f) {
            fprintf(f, "  ftruncate(%lu) = %d errno=%d (%s)\n",
                    sizeof(voice_enhancer::RingBufferSegment), tr, trunc_errno, strerror(trunc_errno));
        }

        errno = 0;
        void* ptr = mmap(nullptr, sizeof(voice_enhancer::RingBufferSegment),
                         PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        int mmap_errno = errno;
        if (f) {
            fprintf(f, "  mmap = %s errno=%d (%s)\n",
                    ptr == MAP_FAILED ? "FAILED" : "OK", mmap_errno, strerror(mmap_errno));
        }

        if (ptr != MAP_FAILED) {
            auto* seg = static_cast<voice_enhancer::RingBufferSegment*>(ptr);
            if (f) {
                fprintf(f, "  magic=0x%08X version=%u rate=%u cap=%u\n",
                        seg->magic, seg->version, seg->sample_rate, seg->capacity_frames);
            }
            munmap(ptr, sizeof(voice_enhancer::RingBufferSegment));
        }
        close(fd);
    }

    // Now try the actual ve_ring_open path
    auto* seg = voice_enhancer::RingBuffer::open_or_create();
    if (f) {
        fprintf(f, "  RingBuffer::open_or_create() = %s\n", seg ? "OK" : "NULL");
        if (seg) {
            fprintf(f, "  magic=0x%08X version=%u rate=%u cap=%u\n",
                    seg->magic, seg->version, seg->sample_rate, seg->capacity_frames);
            voice_enhancer::RingBuffer::close_mapping(seg);
        }
        fclose(f);
    }

    return open_errno;
}
#endif

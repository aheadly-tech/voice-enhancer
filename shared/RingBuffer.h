// Voice Enhancer — shared-memory SPSC ring buffer.
//
// This header is the single source of truth for the IPC protocol between the
// app (producer) and the HAL driver (consumer). Both sides map the same
// POSIX shared-memory segment and interact via the layout defined below.
//
// Design choices:
//
//   * Single-producer single-consumer. The app writes from its audio thread,
//     the driver reads from `coreaudiod`'s I/O cycle. Nothing else touches it.
//     This lets us get away with a pair of relaxed atomics for head/tail and
//     no locking.
//
//   * Fixed layout. We don't allocate inside the ring. The buffer is a flat
//     `float` array of `kRingFrames` samples sitting directly in shared
//     memory. Size is known at compile time and matches on both sides.
//
//   * Mono float32 at 48 kHz. Matches what AudioEngine emits and what the
//     driver advertises. If we ever add stereo or different rates we bump
//     `kProtocolVersion` and both sides refuse to talk across versions.
//
//   * No semaphores. The driver polls at its I/O cycle cadence (~10 ms). If
//     the app isn't writing, the driver reads silence. This is the simplest
//     contract we could design and is plenty for voice work.
//
// Usage, app side (writer):
//
//     auto* seg = RingBuffer::open_or_create();      // creates if needed
//     RingBuffer::write(seg, samples, num_frames);    // RT-safe
//
// Usage, driver side (reader):
//
//     auto* seg = RingBuffer::open();                 // never creates
//     RingBuffer::read(seg, out, num_frames);         // RT-safe; fills with
//                                                     // silence on underrun
//
// The file is ~400 lines because it contains the full implementation. Kept
// as a single header so that nothing else needs to be built or linked on
// either side — the driver already runs in coreaudiod's address space and
// we don't want a shared dylib dangling.

#ifndef VOICE_ENHANCER_SHARED_RING_BUFFER_H
#define VOICE_ENHANCER_SHARED_RING_BUFFER_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>

#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#   include <errno.h>
#   include <fcntl.h>
#   include <sys/mman.h>
#   include <sys/stat.h>
#   include <unistd.h>
#   define VE_RB_HAVE_POSIX 1
#else
#   define VE_RB_HAVE_POSIX 0
#endif

namespace voice_enhancer {

// ---------------------------------------------------------------------------
// Protocol constants. These MUST match on both sides. Changing any of them
// is a breaking change — bump kProtocolVersion and both ends will refuse to
// attach to a mismatched segment.
// ---------------------------------------------------------------------------

// Shared-memory object name. Darwin caps POSIX shm names at 31 bytes, so
// keep this deliberately short or shm_open fails with ENAMETOOLONG.
inline constexpr const char* kRingShmName = "/ve.aheadly.r1";

// Version of the wire format. Bump on any breaking layout change.
inline constexpr std::uint32_t kProtocolVersion = 1;

// Magic number so we can tell a freshly-opened, zero-filled segment from one
// the app has actually initialized. Arbitrary 4-byte ASCII.
inline constexpr std::uint32_t kRingMagic = 0x56454E48;   // 'VENH'

// Sample rate and channel count. Hardcoded; matches the driver's advertised
// format. If we ever need to renegotiate we'll add a control channel.
inline constexpr std::uint32_t kRingSampleRate = 48000;
inline constexpr std::uint32_t kRingChannels   = 1;

// Ring capacity in mono frames. 16384 frames at 48 kHz ≈ 341 ms — large
// enough to absorb macOS scheduling jitter and thermal throttles without
// underrunning the driver. Power-of-two so we can mask instead of modulo.
inline constexpr std::uint32_t kRingFrames = 16384;
static_assert((kRingFrames & (kRingFrames - 1)) == 0,
              "kRingFrames must be a power of two");
inline constexpr std::uint32_t kRingMask   = kRingFrames - 1;

// The HAL's ZeroTimeStampPeriod — how often the driver's clock anchor
// advances. Decoupled from ring capacity so we can size the ring for
// robustness without affecting the HAL timing model.
inline constexpr std::uint32_t kTimestampPeriod = 4096;

// ---------------------------------------------------------------------------
// Segment layout. Laid out for cache-friendly access patterns: the writer
// only touches `write_index`, the reader only touches `read_index`, and the
// two live on separate cache lines to avoid false sharing.
//
// We do NOT use std::atomic<T> types directly inside the struct because on
// some platforms they can carry extra alignment/padding that differs
// between the compiler used by the app and the one used by the driver (which
// coreaudiod loads). Instead we use plain uint32_t fields and do explicit
// atomic load/store via std::atomic_ref-equivalent inline functions. This
// guarantees layout identity across compilers.
// ---------------------------------------------------------------------------

#pragma pack(push, 1)

struct RingBufferSegment {
    std::uint32_t magic;            // kRingMagic, fixed at init time
    std::uint32_t version;          // kProtocolVersion
    std::uint32_t sample_rate;      // kRingSampleRate
    std::uint32_t channels;         // kRingChannels
    std::uint32_t capacity_frames;  // kRingFrames — mirrored for cross-check
    std::uint32_t _reserved;        // keeps header 32 bytes

    // Producer state. Writer updates, reader observes. Placed on its own
    // cache line to dodge false sharing with read_index.
    alignas(64) std::uint32_t write_index;
    std::uint32_t writer_pid;       // set by the app; diagnostic only
    std::uint64_t writer_generation;// incremented every StartIO on the app side
    char _writer_pad[64 - 4 - 4 - 8];

    // Consumer state.
    alignas(64) std::uint32_t read_index;
    std::uint32_t reader_pid;       // set by coreaudiod
    std::uint64_t reader_generation;
    char _reader_pad[64 - 4 - 4 - 8];

    // The audio data itself. One-dimensional, kRingFrames floats.
    alignas(64) float samples[kRingFrames];
};

#pragma pack(pop)

static_assert(sizeof(RingBufferSegment) < (kRingFrames + 64) * sizeof(float) + 512,
              "RingBufferSegment is suspiciously large");

// Atomic helpers. std::atomic_ref is C++20; we're on C++17, so we roll our
// own minimal version using __atomic builtins available on both Clang and
// GCC (and thus on macOS toolchains).

inline std::uint32_t atomic_load_u32(const std::uint32_t* p) noexcept {
    std::uint32_t v;
    __atomic_load(p, &v, __ATOMIC_ACQUIRE);
    return v;
}

inline void atomic_store_u32(std::uint32_t* p, std::uint32_t v) noexcept {
    __atomic_store(p, &v, __ATOMIC_RELEASE);
}

// ---------------------------------------------------------------------------
// Public API. Kept as free functions rather than member functions because
// the segment lives in shared memory and we want zero doubt that the "this"
// pointer is safe to call methods on. Free functions take an explicit
// pointer and that's it.
// ---------------------------------------------------------------------------

class RingBuffer {
public:
    // Open or create the shared segment. Only the app should call this —
    // the app owns the segment's lifetime. Returns nullptr on failure.
    //
    // NOT real-time safe (calls shm_open, ftruncate, mmap). Call once at
    // startup.
    static RingBufferSegment* open_or_create() noexcept {
#if VE_RB_HAVE_POSIX
        const int fd = shm_open(kRingShmName, O_CREAT | O_RDWR, 0666);
        if (fd < 0) return nullptr;

        // coreaudiod doesn't run as the GUI user on modern macOS. Ensure an
        // already-existing segment is writable by both processes instead of
        // inheriting a stale 0600 mode from an older app build.
        (void)fchmod(fd, 0666);

        // Size the file. macOS rounds shm segments up to page boundaries
        // (e.g. 16536 → 32768), and ftruncate returns EINVAL when asked to
        // shrink an already-larger segment. Only call ftruncate when the
        // segment is too small.
        struct stat st;
        if (fstat(fd, &st) != 0) {
            close(fd);
            return nullptr;
        }
        if (st.st_size < static_cast<off_t>(sizeof(RingBufferSegment))) {
            if (ftruncate(fd, static_cast<off_t>(sizeof(RingBufferSegment))) != 0) {
                close(fd);
                return nullptr;
            }
        }

        void* ptr = mmap(nullptr, sizeof(RingBufferSegment),
                         PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        close(fd);    // fd isn't needed once mapped
        if (ptr == MAP_FAILED) return nullptr;

        auto* seg = static_cast<RingBufferSegment*>(ptr);

        // First-use initialization. Guarded by magic check so we don't stomp
        // the segment if the driver happened to initialize it first.
        if (seg->magic != kRingMagic || seg->version != kProtocolVersion) {
            std::memset(seg, 0, sizeof(*seg));
            seg->magic           = kRingMagic;
            seg->version         = kProtocolVersion;
            seg->sample_rate     = kRingSampleRate;
            seg->channels        = kRingChannels;
            seg->capacity_frames = kRingFrames;
        }
        return seg;
#else
        return nullptr;
#endif
    }

    // Open an existing segment read/write. Driver side: returns nullptr if
    // the app hasn't created it yet — caller should retry on the next I/O
    // cycle. NOT real-time safe on the open path.
    static RingBufferSegment* open() noexcept {
#if VE_RB_HAVE_POSIX
        const int fd = shm_open(kRingShmName, O_RDWR, 0600);
        if (fd < 0) return nullptr;

        void* ptr = mmap(nullptr, sizeof(RingBufferSegment),
                         PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        close(fd);
        if (ptr == MAP_FAILED) return nullptr;

        auto* seg = static_cast<RingBufferSegment*>(ptr);
        if (seg->magic != kRingMagic || seg->version != kProtocolVersion) {
            // Segment exists but isn't initialized or is a protocol mismatch.
            // Unmap and tell the caller to retry later.
            munmap(seg, sizeof(RingBufferSegment));
            return nullptr;
        }
        return seg;
#else
        return nullptr;
#endif
    }

    // Unmap a segment previously returned by open() / open_or_create(). Safe
    // to pass nullptr. NOT real-time safe.
    static void close_mapping(RingBufferSegment* seg) noexcept {
#if VE_RB_HAVE_POSIX
        if (seg != nullptr) {
            munmap(seg, sizeof(RingBufferSegment));
        }
#else
        (void)seg;
#endif
    }

    // Remove the shared-memory object from the filesystem. Call on clean app
    // shutdown; the segment persists across restarts otherwise (which is
    // usually what we want, but stale segments survive crashes, so the
    // install/uninstall scripts should also rm it). NOT RT-safe.
    static void unlink_shm() noexcept {
#if VE_RB_HAVE_POSIX
        shm_unlink(kRingShmName);
#endif
    }

    // ---------------------------------------------------------------------
    // Real-time safe producer/consumer ops.
    //
    // These use a classic SPSC ring: the writer owns `write_index`, the
    // reader owns `read_index`. Capacity is `kRingFrames - 1` usable frames
    // so we can tell full from empty.
    //
    // On underrun (reader outpacing writer) the reader fills the tail of
    // the output with zeros. This is how Core Audio's timing model expects
    // us to behave — silence on underrun is better than blocking.
    // ---------------------------------------------------------------------

    // Number of frames currently available to read.
    static std::uint32_t readable(const RingBufferSegment* seg) noexcept {
        const auto r = atomic_load_u32(&seg->read_index);
        const auto w = atomic_load_u32(&seg->write_index);
        return (w - r) & kRingMask;
    }

    // Number of frames we can currently write without overrunning.
    static std::uint32_t writable(const RingBufferSegment* seg) noexcept {
        const auto r = atomic_load_u32(&seg->read_index);
        const auto w = atomic_load_u32(&seg->write_index);
        return (kRingFrames - 1) - ((w - r) & kRingMask);
    }

    // Push `n` frames of audio into the ring. If the ring is nearly full we
    // drop the oldest frames by advancing the read index — we choose this
    // over blocking or dropping the new samples because we are the voice
    // path: the freshest audio is always the most valuable. Dropping old
    // audio produces a single glitch; dropping new audio produces
    // persistent latency creep.
    //
    // RT-safe. No syscalls, no allocations, no locks.
    static void write(RingBufferSegment* seg,
                      const float* src,
                      std::uint32_t num_frames) noexcept {
        if (seg == nullptr || src == nullptr || num_frames == 0) return;

        std::uint32_t w = atomic_load_u32(&seg->write_index);
        const std::uint32_t r = atomic_load_u32(&seg->read_index);

        // If incoming frames would overrun, advance r past the drop region
        // by publishing a new read_index. Since we're SPSC this is normally
        // the reader's privilege, but in an overflow scenario the alternative
        // is silent corruption — we'd rather the reader see a discontinuity
        // than tear-read halfway through our in-flight write.
        const std::uint32_t used = (w - r) & kRingMask;
        const std::uint32_t avail = (kRingFrames - 1) - used;
        if (num_frames > avail) {
            const std::uint32_t to_drop = num_frames - avail;
            atomic_store_u32(&seg->read_index, (r + to_drop) & kRingMask);
        }

        // Contiguous copy, wrapping at the end. Branchless on the common
        // case where the write fits before the wrap.
        const std::uint32_t first = kRingFrames - w;
        if (num_frames <= first) {
            std::memcpy(seg->samples + w, src, num_frames * sizeof(float));
        } else {
            std::memcpy(seg->samples + w, src, first * sizeof(float));
            std::memcpy(seg->samples, src + first,
                        (num_frames - first) * sizeof(float));
        }

        w = (w + num_frames) & kRingMask;
        atomic_store_u32(&seg->write_index, w);
    }

    // Pull up to `num_frames` frames from the ring into `dst`. If fewer are
    // available, the tail of `dst` is filled with zeros (silence on
    // underrun). Returns the number of frames that were live audio
    // (i.e., not silence-padded) so callers can track underruns.
    //
    // RT-safe.
    static std::uint32_t read(const RingBufferSegment* seg,
                              float* dst,
                              std::uint32_t num_frames) noexcept {
        if (seg == nullptr || dst == nullptr || num_frames == 0) return 0;

        const std::uint32_t r = atomic_load_u32(&seg->read_index);
        const std::uint32_t w = atomic_load_u32(&seg->write_index);
        const std::uint32_t available = (w - r) & kRingMask;

        const std::uint32_t take = available < num_frames ? available : num_frames;

        if (take > 0) {
            const std::uint32_t first = kRingFrames - r;
            if (take <= first) {
                std::memcpy(dst, seg->samples + r, take * sizeof(float));
            } else {
                std::memcpy(dst, seg->samples + r, first * sizeof(float));
                std::memcpy(dst + first, seg->samples,
                            (take - first) * sizeof(float));
            }
            atomic_store_u32(const_cast<std::uint32_t*>(&seg->read_index),
                             (r + take) & kRingMask);
        }

        if (take < num_frames) {
            std::memset(dst + take, 0, (num_frames - take) * sizeof(float));
        }
        return take;
    }

    // Bump the writer or reader generation counter. Both sides call this at
    // StartIO time so a stale counterpart can detect "the other side just
    // came back up" and reset its own state if needed. Safe from any thread.
    static void bump_writer_generation(RingBufferSegment* seg) noexcept {
        if (seg == nullptr) return;
        __atomic_add_fetch(&seg->writer_generation, 1, __ATOMIC_RELEASE);
    }
    static void bump_reader_generation(RingBufferSegment* seg) noexcept {
        if (seg == nullptr) return;
        __atomic_add_fetch(&seg->reader_generation, 1, __ATOMIC_RELEASE);
    }
};

} // namespace voice_enhancer

#endif // VOICE_ENHANCER_SHARED_RING_BUFFER_H

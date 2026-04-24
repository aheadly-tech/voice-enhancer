// Plugin-level glue.
//
// Almost every entry point here is a tiny dispatcher: validate the caller,
// route to the appropriate object handler (Plugin / Device / Stream), and
// forward any property queries. The actual behavior lives in Device.cpp and
// Stream.cpp.
//
// This file reads verbosely because Core Audio's C API does. Keep the
// dispatch table surface area small — if a function here grows past ~40
// lines, factor the body into Device.cpp or Stream.cpp.
//
// Shared-memory IPC with the app lives here as well. Opening the ring is
// cheap enough that we do it lazily on the first Read cycle, and we re-try
// on every cycle until the app creates the segment. Closing happens when
// StopIO is called by the last client.

#include "Plugin.h"
#include "Common.h"
#include "Device.h"
#include "Stream.h"
#include "ObjectRegistry.h"

#include "../../shared/RingBuffer.h"

#include <atomic>
#include <cctype>
#include <cstring>
#include <mach/mach_time.h>
#include <os/log.h>

namespace ve_driver {

// ===========================================================================
// Driver-wide state. Accessed from many files via accessors at the bottom.
// All state here is either const after Initialize() or atomic; never take
// a lock in this file.
// ===========================================================================

namespace {

std::atomic<AudioServerPlugInHostRef> g_host {nullptr};

// Ring buffer mapping. Opened on demand — the app might start after us or
// after us repeatedly (restart). Setting this is done from the I/O thread,
// so we use a plain atomic pointer.
std::atomic<voice_enhancer::RingBufferSegment*> g_ring {nullptr};

// Last observed writer generation. When this changes, the app has restarted
// and we must resync our read pointer to avoid reading stale audio.
std::atomic<std::uint64_t> g_last_writer_gen {0};

// IsRunning is what the Device property reports; updated by StartIO /
// StopIO. Using an integer so the atomic load in Device.cpp matches
// kAudioDevicePropertyDeviceIsRunning's UInt32 payload directly.
std::atomic<UInt32> g_io_running {0};

// Client refcount — StartIO/StopIO can be called multiple times by multiple
// clients of the same device. We only start/stop streaming on the 0→1 and
// 1→0 transitions.
std::atomic<int> g_io_client_count {0};

// Timestamp anchor. Core Audio needs us to report "time zero" as a pair
// (sample_time, host_time) that walks forward every "zero timestamp period"
// samples. We model it as a 10 ms cycle: we advance the anchor whenever
// enough wall-clock time has passed since the last anchor, locked to the
// nominal sample rate.
std::atomic<UInt64> g_host_time_at_anchor {0};
std::atomic<Float64> g_sample_time_at_anchor {0.0};

// Cached host-time → nanoseconds conversion. mach_timebase_info is stable
// per boot, so we only fetch it once.
mach_timebase_info_data_t& timebase() noexcept {
    static mach_timebase_info_data_t tb = [] {
        mach_timebase_info_data_t v{};
        mach_timebase_info(&v);
        return v;
    }();
    return tb;
}

os_log_t driver_log() noexcept {
    static os_log_t log = os_log_create("tech.aheadly.voice-enhancer", "driver");
    return log;
}

const char* kind_name(ObjectKind kind) noexcept {
    switch (kind) {
        case ObjectKind::Plugin: return "plugin";
        case ObjectKind::Device: return "device";
        case ObjectKind::Stream: return "stream";
        default: return "unknown";
    }
}

void fourcc_string(UInt32 value, char out[5]) noexcept {
    out[0] = static_cast<char>((value >> 24) & 0xFF);
    out[1] = static_cast<char>((value >> 16) & 0xFF);
    out[2] = static_cast<char>((value >> 8) & 0xFF);
    out[3] = static_cast<char>(value & 0xFF);
    out[4] = '\0';
    for (int i = 0; i < 4; ++i) {
        if (!std::isprint(static_cast<unsigned char>(out[i]))) {
            out[i] = '.';
        }
    }
}

const char* scope_name(UInt32 scope) noexcept {
    switch (scope) {
        case kAudioObjectPropertyScopeGlobal: return "glob";
        case kAudioObjectPropertyScopeInput: return "inpt";
        case kAudioObjectPropertyScopeOutput: return "outp";
        case kAudioObjectPropertyScopePlayThrough: return "ptru";
        default: return "othr";
    }
}

// Convert host ticks to nanoseconds, float64.
Float64 host_ticks_to_ns(UInt64 ticks) noexcept {
    const auto& tb = timebase();
    // (ticks * numer / denom). Use double to avoid overflow at long uptimes.
    return static_cast<Float64>(ticks) *
           (static_cast<Float64>(tb.numer) / static_cast<Float64>(tb.denom));
}

UInt64 ns_to_host_ticks(Float64 ns) noexcept {
    const auto& tb = timebase();
    return static_cast<UInt64>(ns *
           (static_cast<Float64>(tb.denom) / static_cast<Float64>(tb.numer)));
}

// Open the ring buffer if it isn't open yet. RT-callable in the sense that
// it only calls shm_open/mmap the first time — once open, it's a no-op. In
// the worst case (coreaudiod boots before the app) we'll hit the syscalls
// on each cycle until the app creates the segment. That's fine; it's
// bounded to ~100 failed syscalls/second and the stall is orders of
// magnitude below the real-time deadline.
voice_enhancer::RingBufferSegment* ensure_ring() noexcept {
    auto* existing = g_ring.load(std::memory_order_acquire);
    if (existing != nullptr) return existing;

    auto* fresh = voice_enhancer::RingBuffer::open();
    if (fresh == nullptr) return nullptr;

    // Race: another cycle opened it between our load and our open. If so,
    // unmap ours and use theirs.
    voice_enhancer::RingBufferSegment* expected = nullptr;
    if (!g_ring.compare_exchange_strong(expected, fresh,
                                        std::memory_order_acq_rel)) {
        voice_enhancer::RingBuffer::close_mapping(fresh);
        return expected;
    }
    return fresh;
}

// ---------------------------------------------------------------------------
// COM refcount boilerplate. Required by the CFPlugIn machinery.
// ---------------------------------------------------------------------------

std::atomic<int> g_refcount {1};

ULONG AddRef(void*) {
    return static_cast<ULONG>(g_refcount.fetch_add(1, std::memory_order_relaxed) + 1);
}

ULONG Release(void*) {
    const int prev = g_refcount.fetch_sub(1, std::memory_order_acq_rel);
    // We are a singleton owned by the CFPlugIn machinery — we never actually
    // delete ourselves. Apple's sample driver does the same.
    return static_cast<ULONG>(prev - 1);
}

HRESULT QueryInterface(void* /*self*/, REFIID iid, LPVOID* outIface) {
    CFUUIDRef requested_uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    if (requested_uuid == nullptr) return E_NOINTERFACE;

    HRESULT result = E_NOINTERFACE;
    if (CFEqual(requested_uuid, IUnknownUUID) ||
        CFEqual(requested_uuid, kAudioServerPlugInDriverInterfaceUUID)) {
        *outIface = plugin_interface();
        AddRef(nullptr);
        result = 0;
    } else {
        *outIface = nullptr;
    }

    CFRelease(requested_uuid);
    return result;
}

// ---------------------------------------------------------------------------
// AudioServerPlugInDriverInterface — the big one.
// ---------------------------------------------------------------------------

OSStatus Initialize(AudioServerPlugInDriverRef /*drv*/, AudioServerPlugInHostRef host) {
    plugin_set_host(host);

    // Try to map the shared segment now. If the app isn't running yet, this
    // returns nullptr and we'll retry on each cycle. No fatal error either
    // way — the device stays alive, producing silence.
    auto* seg = voice_enhancer::RingBuffer::open();
    g_ring.store(seg, std::memory_order_release);

    // Anchor initial timestamp.
    g_host_time_at_anchor.store(mach_absolute_time(), std::memory_order_relaxed);
    g_sample_time_at_anchor.store(0.0, std::memory_order_relaxed);

    return kAudioHardwareNoError;
}

OSStatus CreateDevice(AudioServerPlugInDriverRef /*drv*/,
                      CFDictionaryRef /*description*/,
                      const AudioServerPlugInClientInfo* /*client*/,
                      AudioObjectID* outDeviceID) {
    // We expose a single, fixed device rather than creating devices on
    // demand, so this call is effectively a no-op that returns our static
    // device ID.
    *outDeviceID = kObjectID_Device;
    return kAudioHardwareNoError;
}

OSStatus DestroyDevice(AudioServerPlugInDriverRef /*drv*/, AudioObjectID /*deviceID*/) {
    // Device is static — nothing to tear down.
    return kAudioHardwareNoError;
}

OSStatus AddDeviceClient(AudioServerPlugInDriverRef /*drv*/,
                         AudioObjectID /*deviceID*/,
                         const AudioServerPlugInClientInfo* /*client*/) {
    // No per-client state. The HAL already tracks clients for us — our
    // clean-shutdown responsibility is handled by matching StopIO calls.
    return kAudioHardwareNoError;
}

OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef /*drv*/,
                            AudioObjectID /*deviceID*/,
                            const AudioServerPlugInClientInfo* /*client*/) {
    return kAudioHardwareNoError;
}

OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef /*drv*/,
                                          AudioObjectID /*deviceID*/,
                                          UInt64 /*changeAction*/,
                                          void* /*changeInfo*/) {
    // We only support one format and one sample rate — there's no
    // negotiation for us to perform. The HAL still calls this after a
    // SetPropertyData on NominalSampleRate; by returning NoError we signal
    // "change accepted, no reconfiguration needed on our side".
    return kAudioHardwareNoError;
}

OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef /*drv*/,
                                        AudioObjectID /*deviceID*/,
                                        UInt64 /*changeAction*/,
                                        void* /*changeInfo*/) {
    return kAudioHardwareNoError;
}

// ---------------------------------------------------------------------------
// Property API — dispatch by object kind.
// ---------------------------------------------------------------------------

Boolean HasProperty(AudioServerPlugInDriverRef /*drv*/,
                    AudioObjectID obj,
                    pid_t /*clientPID*/,
                    const AudioObjectPropertyAddress* addr) {
    const ObjectKind kind = classify_object(obj);
    Boolean hasProperty = false;
    switch (kind) {
        case ObjectKind::Plugin: hasProperty = plugin_has_property(*addr); break;
        case ObjectKind::Device: hasProperty = device_has_property(*addr); break;
        case ObjectKind::Stream: hasProperty = stream_has_property(*addr); break;
        default: hasProperty = false; break;
    }

    char selector[5];
    fourcc_string(addr->mSelector, selector);
    os_log_info(driver_log(),
                "HasProperty kind=%{public}s obj=%u sel=%{public}s scope=%{public}s has=%{public}d",
                kind_name(kind), obj, selector, scope_name(addr->mScope), hasProperty);
    return hasProperty;
}

OSStatus IsPropertySettable(AudioServerPlugInDriverRef /*drv*/,
                            AudioObjectID obj,
                            pid_t /*clientPID*/,
                            const AudioObjectPropertyAddress* addr,
                            Boolean* outIsSettable) {
    const ObjectKind kind = classify_object(obj);
    OSStatus status = kAudioHardwareNoError;
    switch (kind) {
        case ObjectKind::Plugin: *outIsSettable = plugin_is_property_settable(*addr); break;
        case ObjectKind::Device: *outIsSettable = device_is_property_settable(*addr); break;
        case ObjectKind::Stream: *outIsSettable = stream_is_property_settable(*addr); break;
        default:
            status = kAudioHardwareBadObjectError;
            break;
    }

    char selector[5];
    fourcc_string(addr->mSelector, selector);
    os_log_info(driver_log(),
                "IsPropertySettable kind=%{public}s obj=%u sel=%{public}s scope=%{public}s status=%d settable=%{public}d",
                kind_name(kind), obj, selector, scope_name(addr->mScope), status,
                (status == kAudioHardwareNoError) ? *outIsSettable : 0);
    return status;
}

OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef /*drv*/,
                             AudioObjectID obj,
                             pid_t /*clientPID*/,
                             const AudioObjectPropertyAddress* addr,
                             UInt32 qualSize, const void* qual,
                             UInt32* outSize) {
    const ObjectKind kind = classify_object(obj);
    OSStatus status = kAudioHardwareBadObjectError;
    switch (kind) {
        case ObjectKind::Plugin: status = plugin_get_property_data_size(*addr, qualSize, qual, *outSize); break;
        case ObjectKind::Device: status = device_get_property_data_size(*addr, qualSize, qual, *outSize); break;
        case ObjectKind::Stream: status = stream_get_property_data_size(*addr, qualSize, qual, *outSize); break;
        default: break;
    }

    char selector[5];
    fourcc_string(addr->mSelector, selector);
    os_log_info(driver_log(),
                "GetPropertyDataSize kind=%{public}s obj=%u sel=%{public}s scope=%{public}s qual=%u status=%d size=%u",
                kind_name(kind), obj, selector, scope_name(addr->mScope), qualSize, status,
                (status == kAudioHardwareNoError) ? *outSize : 0);
    return status;
}

OSStatus GetPropertyData(AudioServerPlugInDriverRef /*drv*/,
                         AudioObjectID obj,
                         pid_t /*clientPID*/,
                         const AudioObjectPropertyAddress* addr,
                         UInt32 qualSize, const void* qual,
                         UInt32 dataSize, UInt32* outUsed, void* outData) {
    const ObjectKind kind = classify_object(obj);
    OSStatus status = kAudioHardwareBadObjectError;
    switch (kind) {
        case ObjectKind::Plugin: status = plugin_get_property_data(*addr, qualSize, qual, dataSize, *outUsed, outData); break;
        case ObjectKind::Device: status = device_get_property_data(*addr, qualSize, qual, dataSize, *outUsed, outData); break;
        case ObjectKind::Stream: status = stream_get_property_data(*addr, qualSize, qual, dataSize, *outUsed, outData); break;
        default: break;
    }

    char selector[5];
    fourcc_string(addr->mSelector, selector);
    os_log_info(driver_log(),
                "GetPropertyData kind=%{public}s obj=%u sel=%{public}s scope=%{public}s qual=%u req=%u status=%d used=%u",
                kind_name(kind), obj, selector, scope_name(addr->mScope), qualSize, dataSize,
                status, (status == kAudioHardwareNoError) ? *outUsed : 0);
    return status;
}

OSStatus SetPropertyData(AudioServerPlugInDriverRef /*drv*/,
                         AudioObjectID obj,
                         pid_t /*clientPID*/,
                         const AudioObjectPropertyAddress* addr,
                         UInt32 qualSize, const void* qual,
                         UInt32 dataSize, const void* data) {
    const ObjectKind kind = classify_object(obj);
    OSStatus status = kAudioHardwareUnsupportedOperationError;
    switch (kind) {
        case ObjectKind::Device: status = device_set_property_data(*addr, qualSize, qual, dataSize, data); break;
        case ObjectKind::Stream: status = stream_set_property_data(*addr, qualSize, qual, dataSize, data); break;
        default: break;
    }

    char selector[5];
    fourcc_string(addr->mSelector, selector);
    os_log_info(driver_log(),
                "SetPropertyData kind=%{public}s obj=%u sel=%{public}s scope=%{public}s qual=%u data=%u status=%d",
                kind_name(kind), obj, selector, scope_name(addr->mScope), qualSize, dataSize,
                status);
    return status;
}

// ---------------------------------------------------------------------------
// I/O cycle — the hot path.
// ---------------------------------------------------------------------------

OSStatus StartIO(AudioServerPlugInDriverRef /*drv*/,
                 AudioObjectID /*deviceID*/, UInt32 /*clientID*/) {
    const int prev = g_io_client_count.fetch_add(1, std::memory_order_acq_rel);
    if (prev == 0) {
        // First client. Reset the timestamp anchor and try (again) to open
        // the ring. Bumping the reader generation lets the app side know
        // we just came up if it wants to resync.
        g_host_time_at_anchor.store(mach_absolute_time(), std::memory_order_relaxed);
        g_sample_time_at_anchor.store(0.0, std::memory_order_relaxed);

        if (g_ring.load(std::memory_order_acquire) == nullptr) {
            auto* seg = voice_enhancer::RingBuffer::open();
            if (seg != nullptr) {
                g_ring.store(seg, std::memory_order_release);
            }
        }
        auto* seg = g_ring.load(std::memory_order_acquire);
        if (seg != nullptr) {
            voice_enhancer::RingBuffer::bump_reader_generation(seg);
        }
        g_io_running.store(1, std::memory_order_release);
    }
    return kAudioHardwareNoError;
}

OSStatus StopIO(AudioServerPlugInDriverRef /*drv*/,
                AudioObjectID /*deviceID*/, UInt32 /*clientID*/) {
    const int prev = g_io_client_count.fetch_sub(1, std::memory_order_acq_rel);
    if (prev == 1) {
        g_io_running.store(0, std::memory_order_release);
    } else if (prev < 1) {
        // Unbalanced — the HAL called StopIO more than StartIO. Clamp at
        // zero and treat it as a no-op. This is defensive; coreaudiod
        // should never do this but at least we won't go negative.
        g_io_client_count.store(0, std::memory_order_release);
    }
    return kAudioHardwareNoError;
}

OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef /*drv*/,
                          AudioObjectID /*deviceID*/, UInt32 /*clientID*/,
                          Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    // Core Audio uses these as the anchor for its sample-accurate timing
    // math. The contract is: return the (sample_time, host_time) pair that
    // is known to have been the device's position at some past cycle, and
    // advance it monotonically.
    //
    // We advance the anchor at ZeroTimeStampPeriod intervals (see Device.cpp
    // for the value — equal to our ring capacity). If enough wall-clock time
    // has passed since the last anchor, bump both coordinates in lock-step.

    const UInt64 now_ticks     = mach_absolute_time();
    const UInt64 anchor_ticks  = g_host_time_at_anchor.load(std::memory_order_relaxed);
    const Float64 anchor_samp  = g_sample_time_at_anchor.load(std::memory_order_relaxed);

    // Compute elapsed ns, convert to frames at our nominal sample rate.
    const Float64 elapsed_ns   = host_ticks_to_ns(now_ticks - anchor_ticks);
    const Float64 elapsed_frames = elapsed_ns * (kSampleRate / 1.0e9);

    // Period in frames matches kTimestampPeriod (decoupled from ring
    // capacity). We move the anchor forward by whole periods only —
    // partial moves would make the reported timestamp wobble.
    constexpr Float64 period = static_cast<Float64>(voice_enhancer::kTimestampPeriod);
    if (elapsed_frames >= period) {
        const Float64 whole_periods = static_cast<Float64>(
            static_cast<UInt64>(elapsed_frames / period));
        const Float64 new_samp  = anchor_samp + whole_periods * period;
        const Float64 advance_ns = (whole_periods * period) * (1.0e9 / kSampleRate);
        const UInt64 new_ticks  = anchor_ticks + ns_to_host_ticks(advance_ns);

        g_sample_time_at_anchor.store(new_samp, std::memory_order_relaxed);
        g_host_time_at_anchor.store  (new_ticks, std::memory_order_relaxed);

        *outSampleTime = new_samp;
        *outHostTime   = new_ticks;
    } else {
        *outSampleTime = anchor_samp;
        *outHostTime   = anchor_ticks;
    }
    // Seed is constant — our zero timestamp generation mechanism never
    // jumps discontinuously, so clients don't need to reset.
    *outSeed = 1;

    return kAudioHardwareNoError;
}

OSStatus WillDoIOOperation(AudioServerPlugInDriverRef /*drv*/,
                           AudioObjectID /*deviceID*/, UInt32 /*clientID*/,
                           UInt32 op, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    // We handle ReadInput only (we are a virtual microphone).
    *outWillDo = (op == kAudioServerPlugInIOOperationReadInput);
    *outWillDoInPlace = true;
    return kAudioHardwareNoError;
}

OSStatus BeginIOOperation(AudioServerPlugInDriverRef /*drv*/,
                          AudioObjectID, UInt32, UInt32, UInt32,
                          const AudioServerPlugInIOCycleInfo*) {
    return kAudioHardwareNoError;
}

OSStatus DoIOOperation(AudioServerPlugInDriverRef /*drv*/,
                       AudioObjectID /*deviceID*/, AudioObjectID /*streamID*/,
                       UInt32 /*clientID*/, UInt32 op,
                       UInt32 ioBufferFrameSize,
                       const AudioServerPlugInIOCycleInfo* /*cycleInfo*/,
                       void* ioMainBuffer, void* /*ioSecondaryBuffer*/) {
    if (op != kAudioServerPlugInIOOperationReadInput || ioMainBuffer == nullptr) {
        return kAudioHardwareNoError;
    }

    // Pull from the ring. ensure_ring() is a noop after first success; on
    // the first few cycles (before the app runs) it will fail and we'll
    // deliver silence, which is exactly what we want.
    auto* seg = ensure_ring();

    float* const dst = static_cast<float*>(ioMainBuffer);
    const std::uint32_t frames = static_cast<std::uint32_t>(ioBufferFrameSize);

    if (seg == nullptr) {
        std::memset(dst, 0, frames * kBytesPerFrame * kChannelsPerFrame);
        return kAudioHardwareNoError;
    }

    // Detect app restart: if writer_generation changed, the app re-created
    // its session. Snap our read pointer to the current write pointer so we
    // don't read stale audio left over from the previous session.
    std::uint64_t wgen = 0;
    __atomic_load(&seg->writer_generation, &wgen, __ATOMIC_ACQUIRE);
    const std::uint64_t prev_gen = g_last_writer_gen.load(std::memory_order_relaxed);
    if (wgen != prev_gen) {
        g_last_writer_gen.store(wgen, std::memory_order_relaxed);
        const auto w = voice_enhancer::atomic_load_u32(&seg->write_index);
        voice_enhancer::atomic_store_u32(
            const_cast<std::uint32_t*>(&seg->read_index), w);
    }

    voice_enhancer::RingBuffer::read(seg, dst, frames);
    return kAudioHardwareNoError;
}

OSStatus EndIOOperation(AudioServerPlugInDriverRef /*drv*/,
                        AudioObjectID, UInt32, UInt32, UInt32,
                        const AudioServerPlugInIOCycleInfo*) {
    return kAudioHardwareNoError;
}

// ---------------------------------------------------------------------------
// Vtable — declared here, referenced from Entry.cpp.
// ---------------------------------------------------------------------------

AudioServerPlugInDriverInterface g_interface = {
    nullptr,                                // _reserved
    QueryInterface,
    AddRef,
    Release,
    Initialize,
    CreateDevice,
    DestroyDevice,
    AddDeviceClient,
    RemoveDeviceClient,
    PerformDeviceConfigurationChange,
    AbortDeviceConfigurationChange,
    HasProperty,
    IsPropertySettable,
    GetPropertyDataSize,
    GetPropertyData,
    SetPropertyData,
    StartIO,
    StopIO,
    GetZeroTimeStamp,
    WillDoIOOperation,
    BeginIOOperation,
    DoIOOperation,
    EndIOOperation,
};

AudioServerPlugInDriverInterface* g_driver_interface = &g_interface;

} // anonymous namespace

AudioServerPlugInDriverRef plugin_interface() noexcept {
    return &g_driver_interface;
}

void plugin_set_host(AudioServerPlugInHostRef host) noexcept {
    g_host.store(host, std::memory_order_relaxed);
}

AudioServerPlugInHostRef plugin_get_host() noexcept {
    return g_host.load(std::memory_order_relaxed);
}

UInt32 plugin_io_is_running() noexcept {
    return g_io_running.load(std::memory_order_acquire);
}

} // namespace ve_driver

// ===========================================================================
// Plugin-object property handlers.
//
// The Core Audio HAL treats the plugin itself as an object with properties.
// These queries arrive before it drills down into the device. Implementing
// them correctly is what lets the plugin appear at all in system_profiler
// and the Settings → Sound UI.
// ===========================================================================

namespace ve_driver {

namespace {

// Helper to write a CFString property into a caller's buffer.
OSStatus write_cfstring(const char* s, UInt32 dataSize, UInt32& outUsed, void* outData) {
    if (dataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
    *static_cast<CFStringRef*>(outData) =
        CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8);
    outUsed = sizeof(CFStringRef);
    return kAudioHardwareNoError;
}

bool qualifier_includes_class(UInt32 qualSize,
                              const void* qual,
                              AudioClassID objectClass,
                              AudioClassID objectBaseClass) noexcept {
    if (qualSize == 0 || qual == nullptr) return true;
    if ((qualSize % sizeof(AudioClassID)) != 0) return false;

    const auto count = qualSize / sizeof(AudioClassID);
    const auto* classes = static_cast<const AudioClassID*>(qual);
    for (UInt32 i = 0; i < count; ++i) {
        if (classes[i] == objectClass || classes[i] == objectBaseClass) {
            return true;
        }
    }
    return false;
}

} // anonymous namespace

bool plugin_has_property(const AudioObjectPropertyAddress& addr) noexcept {
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyBundleID:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
            return true;
        default:
            return false;
    }
}

bool plugin_is_property_settable(const AudioObjectPropertyAddress& /*addr*/) noexcept {
    return false;
}

OSStatus plugin_get_property_data_size(const AudioObjectPropertyAddress& addr,
                                       UInt32 qualSize, const void* qual,
                                       UInt32& outSize) noexcept {
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyOwner:
            outSize = sizeof(AudioClassID);
            return kAudioHardwareNoError;

        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyBundleID:
        case kAudioPlugInPropertyResourceBundle:
            outSize = sizeof(CFStringRef);
            return kAudioHardwareNoError;

        case kAudioObjectPropertyOwnedObjects:
            outSize = qualifier_includes_class(qualSize, qual,
                                               kAudioDeviceClassID,
                                               kAudioObjectClassID)
                      ? sizeof(AudioObjectID)
                      : 0;
            return kAudioHardwareNoError;

        case kAudioPlugInPropertyDeviceList:
            outSize = sizeof(AudioObjectID);
            return kAudioHardwareNoError;

        case kAudioPlugInPropertyTranslateUIDToDevice:
            outSize = sizeof(AudioObjectID);
            return kAudioHardwareNoError;

        default:
            outSize = 0;
            return kAudioHardwareUnknownPropertyError;
    }
}

OSStatus plugin_get_property_data(const AudioObjectPropertyAddress& addr,
                                  UInt32 qualSize, const void* qual,
                                  UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    outUsed = 0;
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioPlugInClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyBaseClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioObjectClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyOwner: {
            // The plugin is the root object; it has no owner.
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kAudioObjectUnknown;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyName:
            return write_cfstring(kDeviceName, dataSize, outUsed, outData);
        case kAudioObjectPropertyManufacturer:
            return write_cfstring(kManufacturer, dataSize, outUsed, outData);
        case kAudioPlugInPropertyBundleID:
            return write_cfstring(kBundleId, dataSize, outUsed, outData);
        case kAudioPlugInPropertyResourceBundle: {
            // Empty string means "use the plugin's own bundle" — the
            // default is correct for our layout.
            return write_cfstring("", dataSize, outUsed, outData);
        }
        case kAudioObjectPropertyOwnedObjects: {
            if (!qualifier_includes_class(qualSize, qual,
                                          kAudioDeviceClassID,
                                          kAudioObjectClassID)) {
                outUsed = 0;
                return kAudioHardwareNoError;
            }
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Device;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioPlugInPropertyDeviceList: {
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Device;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            // Input: CFStringRef UID. Output: matching AudioObjectID.
            if (qualSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            auto uid = *static_cast<const CFStringRef*>(qual);
            CFStringRef ours = CFStringCreateWithCString(
                kCFAllocatorDefault, kDeviceUID, kCFStringEncodingUTF8);
            const Boolean match = (uid != nullptr) &&
                CFStringCompare(uid, ours, 0) == kCFCompareEqualTo;
            CFRelease(ours);
            *static_cast<AudioObjectID*>(outData) =
                match ? kObjectID_Device : kAudioObjectUnknown;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

} // namespace ve_driver

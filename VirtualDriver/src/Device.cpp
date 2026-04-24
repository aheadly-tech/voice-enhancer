// Device property implementation.
//
// A Core Audio device has roughly thirty properties that the HAL or a
// client may query. The full matrix is documented in
// <CoreAudio/AudioHardware.h> under the kAudioDevicePropertyXxx
// identifiers. This file implements every property needed for the device
// to behave correctly as a virtual microphone across the apps we care
// about (Zoom, Teams, Meet, Discord, OBS, QuickTime).
//
// Organizing principle: group properties by purpose (identity, audio
// format, IO policy, channel geometry) rather than by data type. The
// switch statements get long but the grouping keeps related knobs together.

#include "Device.h"
#include "Common.h"
#include "Plugin.h"

#include "../../shared/RingBuffer.h"

#include <CoreAudio/AudioHardware.h>
#include <cstring>

namespace ve_driver {

namespace {

// --------------------------------------------------------------------------
// Small helpers so the switch arms don't repeat boilerplate.
// --------------------------------------------------------------------------

OSStatus write_u32(UInt32 value, UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    if (dataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
    *static_cast<UInt32*>(outData) = value;
    outUsed = sizeof(UInt32);
    return kAudioHardwareNoError;
}

OSStatus write_f64(Float64 value, UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    if (dataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
    *static_cast<Float64*>(outData) = value;
    outUsed = sizeof(Float64);
    return kAudioHardwareNoError;
}

OSStatus write_cfstring(const char* s, UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    if (dataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
    *static_cast<CFStringRef*>(outData) =
        CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8);
    outUsed = sizeof(CFStringRef);
    return kAudioHardwareNoError;
}

// The driver's configuration application — the macOS Settings pane
// that Core Audio points the user at when they click "Configure" in the
// device picker. We point at our app. macOS will look it up by bundle ID.
inline constexpr const char* kConfigurationAppBundleId =
    "tech.aheadly.voice-enhancer";

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

// ===========================================================================
// HasProperty — answer the HAL's "do you support this?" question.
//
// Returning true commits us to returning a size and data for the same
// address in GetPropertyDataSize / GetPropertyData. Inconsistency will
// crash coreaudiod. When in doubt, return false and add support
// incrementally — but be aware that picky clients (particularly those
// using the old C++ CoreAudio wrappers) will refuse the device if we
// don't implement a "common" property.
// ===========================================================================

bool device_has_property(const AudioObjectPropertyAddress& addr) noexcept {
    switch (addr.mSelector) {
        // Identity
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:

        // Transport / lifecycle
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyConfigurationApplication:

        // Audio format / sample rate
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:

        // Buffer / timing
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyBufferFrameSizeRange:
        case kAudioDevicePropertyZeroTimeStampPeriod:

        // Channel geometry
        case kAudioDevicePropertyPreferredChannelsForStereo:
        case kAudioDevicePropertyPreferredChannelLayout:

        // Stream hierarchy
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyStreams:
            return true;

        // Deliberately NOT supported — returning false here is correct:
        //   * kAudioDevicePropertyIcon: we could ship one, but an empty
        //     implementation keeps the bundle lean. macOS falls back to a
        //     generic mic icon which looks fine.
        //   * kAudioDeviceProcessorOverload: we aren't a hardware device.
        default:
            return false;
    }
}

// ===========================================================================
// IsPropertySettable
//
// The HAL expects NominalSampleRate and BufferFrameSize to be settable on
// any well-behaved device — even if we accept only one value. Returning
// false unconditionally makes some clients (notably the legacy CA public
// utility) reject the device at selection time.
// ===========================================================================

bool device_is_property_settable(const AudioObjectPropertyAddress& addr) noexcept {
    switch (addr.mSelector) {
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyBufferFrameSize:
            return true;
        default:
            return false;
    }
}

// ===========================================================================
// Sizes.
// ===========================================================================

OSStatus device_get_property_data_size(const AudioObjectPropertyAddress& addr,
                                       UInt32 qualSize, const void* qual,
                                       UInt32& outSize) noexcept {
    switch (addr.mSelector) {
        // CFStringRef payloads
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyConfigurationApplication:
            outSize = sizeof(CFStringRef);
            return kAudioHardwareNoError;

        // AudioClassID payloads
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
            outSize = sizeof(AudioClassID);
            return kAudioHardwareNoError;

        // UInt32 payloads
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyZeroTimeStampPeriod:
            outSize = sizeof(UInt32);
            return kAudioHardwareNoError;

        // Float64 payloads
        case kAudioDevicePropertyNominalSampleRate:
            outSize = sizeof(Float64);
            return kAudioHardwareNoError;

        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyBufferFrameSizeRange:
            // One range value, matching our single supported rate/size.
            outSize = sizeof(AudioValueRange);
            return kAudioHardwareNoError;

        case kAudioObjectPropertyOwner: {
            outSize = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }

        case kAudioObjectPropertyOwnedObjects:
            outSize = qualifier_includes_class(qualSize, qual,
                                               kAudioStreamClassID,
                                               kAudioObjectClassID)
                      ? sizeof(AudioObjectID)
                      : 0;
            return kAudioHardwareNoError;

        case kAudioObjectPropertyControlList:
            outSize = 0;
            return kAudioHardwareNoError;

        case kAudioDevicePropertyStreams:
            // We own exactly one stream. Only the input scope lists it;
            // output scope returns zero length.
            outSize = (addr.mScope == kAudioObjectPropertyScopeOutput)
                      ? 0
                      : sizeof(AudioObjectID);
            return kAudioHardwareNoError;

        case kAudioDevicePropertyRelatedDevices:
            outSize = 0;
            return kAudioHardwareNoError;

        case kAudioDevicePropertyPreferredChannelsForStereo:
            // Two UInt32s: left-channel and right-channel indices. Required
            // even though we present mono — some apps read this unconditionally.
            outSize = sizeof(UInt32) * 2;
            return kAudioHardwareNoError;

        case kAudioDevicePropertyPreferredChannelLayout: {
            // AudioChannelLayout with a single mono descriptor.
            outSize = sizeof(AudioChannelLayout);
            return kAudioHardwareNoError;
        }

        default:
            outSize = 0;
            return kAudioHardwareUnknownPropertyError;
    }
}

// ===========================================================================
// GetPropertyData — the fat switch.
//
// Keep arms in the same order as the HasProperty switch so a missing case
// is obvious.
// ===========================================================================

OSStatus device_get_property_data(const AudioObjectPropertyAddress& addr,
                                  UInt32 qualSize, const void* qual,
                                  UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    outUsed = 0;
    switch (addr.mSelector) {

        // -------- Identity --------

        case kAudioObjectPropertyClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioDeviceClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyBaseClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioObjectClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyName:
            return write_cfstring(kDeviceName, dataSize, outUsed, outData);
        case kAudioObjectPropertyManufacturer:
            return write_cfstring(kManufacturer, dataSize, outUsed, outData);
        case kAudioDevicePropertyDeviceUID:
            return write_cfstring(kDeviceUID, dataSize, outUsed, outData);
        case kAudioDevicePropertyModelUID:
            // Bundle ID as model UID is standard for plugin devices.
            return write_cfstring(kBundleId, dataSize, outUsed, outData);
        case kAudioObjectPropertyOwner: {
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Plugin;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }

        // -------- Transport / lifecycle --------

        case kAudioDevicePropertyTransportType:
            return write_u32(kAudioDeviceTransportTypeVirtual, dataSize, outUsed, outData);
        case kAudioDevicePropertyClockDomain:
            // 0 = self-clocking (nothing else shares our clock).
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioDevicePropertyDeviceIsAlive:
            return write_u32(1, dataSize, outUsed, outData);
        case kAudioDevicePropertyDeviceIsRunning:
            return write_u32(plugin_io_is_running(), dataSize, outUsed, outData);
        case kAudioDevicePropertyIsHidden:
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
            // 1 for the input scope: yes, we can be the default mic.
            // 0 for output scope: we have no output.
            return write_u32(addr.mScope == kAudioObjectPropertyScopeOutput ? 0 : 1,
                             dataSize, outUsed, outData);
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            // "System" default = the device used for system sounds (alerts).
            // Voice Enhancer is a comms device, not a sound-effects device.
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioDevicePropertyConfigurationApplication:
            return write_cfstring(kConfigurationAppBundleId, dataSize, outUsed, outData);

        // -------- Audio format / sample rate --------

        case kAudioDevicePropertyNominalSampleRate:
            return write_f64(kSampleRate, dataSize, outUsed, outData);
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            if (dataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            auto* r = static_cast<AudioValueRange*>(outData);
            r->mMinimum = kSampleRate;
            r->mMaximum = kSampleRate;
            outUsed = sizeof(AudioValueRange);
            return kAudioHardwareNoError;
        }

        // -------- Buffer / timing --------

        case kAudioDevicePropertyLatency:
            // Virtual device: input-to-output delay is the ring buffer fill
            // level. We report zero because the ring is intentionally run
            // with very little back-pressure — latency shows up as ring
            // depth, not as added samples. Apps that need precise timing
            // can compensate with SafetyOffset below.
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioDevicePropertySafetyOffset:
            // Samples of clock slop clients should tolerate. 0 is fine for
            // a self-paced virtual device.
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioDevicePropertyBufferFrameSize:
            // Nominal buffer size. Clients may change it within the range
            // below. 512 is a sensible default for voice at 48 kHz.
            return write_u32(512, dataSize, outUsed, outData);
        case kAudioDevicePropertyBufferFrameSizeRange: {
            if (dataSize < sizeof(AudioValueRange)) return kAudioHardwareBadPropertySizeError;
            auto* r = static_cast<AudioValueRange*>(outData);
            r->mMinimum = 32;
            r->mMaximum = static_cast<Float64>(voice_enhancer::kTimestampPeriod / 2);
            outUsed = sizeof(AudioValueRange);
            return kAudioHardwareNoError;
        }
        case kAudioDevicePropertyZeroTimeStampPeriod:
            // Must match the cadence at which GetZeroTimeStamp advances its
            // anchor. Decoupled from ring capacity so we can size the ring
            // independently for robustness.
            return write_u32(static_cast<UInt32>(voice_enhancer::kTimestampPeriod),
                             dataSize, outUsed, outData);

        // -------- Channel geometry --------

        case kAudioDevicePropertyPreferredChannelsForStereo: {
            if (dataSize < sizeof(UInt32) * 2) return kAudioHardwareBadPropertySizeError;
            auto* p = static_cast<UInt32*>(outData);
            // 1-indexed channels. For a mono device, both "left" and "right"
            // of a stereo pair map to our single channel.
            p[0] = 1;
            p[1] = 1;
            outUsed = sizeof(UInt32) * 2;
            return kAudioHardwareNoError;
        }
        case kAudioDevicePropertyPreferredChannelLayout: {
            if (dataSize < sizeof(AudioChannelLayout)) return kAudioHardwareBadPropertySizeError;
            auto* layout = static_cast<AudioChannelLayout*>(outData);
            std::memset(layout, 0, sizeof(*layout));
            layout->mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
            layout->mChannelBitmap     = 0;
            layout->mNumberChannelDescriptions = 0;
            outUsed = sizeof(AudioChannelLayout);
            return kAudioHardwareNoError;
        }

        // -------- Stream hierarchy --------

        case kAudioObjectPropertyOwnedObjects: {
            if (!qualifier_includes_class(qualSize, qual,
                                          kAudioStreamClassID,
                                          kAudioObjectClassID)) {
                outUsed = 0;
                return kAudioHardwareNoError;
            }
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Stream;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyControlList:
            outUsed = 0;
            return kAudioHardwareNoError;
        case kAudioDevicePropertyStreams: {
            // Input scope returns the one stream. Output scope is empty.
            if (addr.mScope == kAudioObjectPropertyScopeOutput) {
                outUsed = 0;
                return kAudioHardwareNoError;
            }
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Stream;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioDevicePropertyRelatedDevices:
            outUsed = 0;
            return kAudioHardwareNoError;

        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

// ===========================================================================
// SetPropertyData
//
// Settable properties: NominalSampleRate and BufferFrameSize. We enforce
// our single supported value for the sample rate and clamp buffer size to
// our advertised range; writing an unsupported value returns an error the
// client can recognize ("illegal operation") rather than silently ignoring.
// ===========================================================================

OSStatus device_set_property_data(const AudioObjectPropertyAddress& addr,
                                  UInt32 /*qualSize*/, const void* /*qual*/,
                                  UInt32 dataSize, const void* data) noexcept {
    switch (addr.mSelector) {
        case kAudioDevicePropertyNominalSampleRate: {
            if (dataSize < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
            const Float64 requested = *static_cast<const Float64*>(data);
            // Accept only our one rate. Returning success for the same value
            // is important — clients probe by writing the current value back.
            if (requested == kSampleRate) return kAudioHardwareNoError;
            return kAudioHardwareIllegalOperationError;
        }
        case kAudioDevicePropertyBufferFrameSize: {
            if (dataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            const UInt32 req = *static_cast<const UInt32*>(data);
            if (req < 32 || req > voice_enhancer::kTimestampPeriod / 2) {
                return kAudioHardwareIllegalOperationError;
            }
            // We don't actually change anything internally — our IO layer
            // pulls whatever the HAL asks for on each cycle. Reporting the
            // request back in subsequent gets would be more faithful, but
            // costs state for no benefit. Returning NoError accepts the
            // new size implicitly.
            return kAudioHardwareNoError;
        }
        default:
            return kAudioHardwareUnsupportedOperationError;
    }
}

} // namespace ve_driver

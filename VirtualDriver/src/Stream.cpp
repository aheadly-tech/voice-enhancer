// Stream property implementation.
//
// Streams are simpler than devices — the big property is the physical /
// virtual audio format, which we advertise as 48 kHz mono float32. Clients
// may write the format back; we accept only our one supported format and
// reject anything else. Same deal for IsActive.

#include "Stream.h"
#include "Common.h"

#include <atomic>
#include <cstring>

namespace ve_driver {

namespace {

// Streams expose "active" independent of the device's running state. We
// track it per-stream via a simple atomic and report it on query.
std::atomic<UInt32> g_stream_active {1};

AudioStreamBasicDescription make_stream_format() noexcept {
    AudioStreamBasicDescription asbd{};
    asbd.mSampleRate       = kSampleRate;
    asbd.mFormatID         = kAudioFormatLinearPCM;
    asbd.mFormatFlags      = kAudioFormatFlagIsFloat
                           | kAudioFormatFlagIsPacked
                           | kAudioFormatFlagsNativeEndian;
    asbd.mBytesPerPacket   = kBytesPerFrame * kChannelsPerFrame;
    asbd.mFramesPerPacket  = kFramesPerPacket;
    asbd.mBytesPerFrame    = kBytesPerFrame * kChannelsPerFrame;
    asbd.mChannelsPerFrame = kChannelsPerFrame;
    asbd.mBitsPerChannel   = kBitsPerChannel;
    return asbd;
}

// Compare two ASBDs for our "this is the one format we support" check. We
// compare the fields that define the on-wire meaning of samples; flags like
// alignment that the OS may normalize before handing them to us are
// excluded.
bool is_our_format(const AudioStreamBasicDescription& a) noexcept {
    return a.mSampleRate       == kSampleRate
        && a.mFormatID         == kAudioFormatLinearPCM
        && (a.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        && a.mChannelsPerFrame == kChannelsPerFrame
        && a.mBitsPerChannel   == kBitsPerChannel;
}

OSStatus write_u32(UInt32 v, UInt32 sz, UInt32& used, void* out) noexcept {
    if (sz < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
    *static_cast<UInt32*>(out) = v;
    used = sizeof(UInt32);
    return kAudioHardwareNoError;
}

} // anonymous namespace

// ===========================================================================
// HasProperty
// ===========================================================================

bool stream_has_property(const AudioObjectPropertyAddress& addr) noexcept {
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyOwner:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        default:
            return false;
    }
}

// ===========================================================================
// IsPropertySettable
//
// Formats and IsActive are settable. We reject formats that don't match
// our single supported one, but we have to answer "yes, settable" on the
// query for well-behaved clients (including AVAudioEngine).
// ===========================================================================

bool stream_is_property_settable(const AudioObjectPropertyAddress& addr) noexcept {
    switch (addr.mSelector) {
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            return true;
        default:
            return false;
    }
}

// ===========================================================================
// Sizes
// ===========================================================================

OSStatus stream_get_property_data_size(const AudioObjectPropertyAddress& addr,
                                       UInt32, const void*, UInt32& outSize) noexcept {
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyBaseClass:
            outSize = sizeof(AudioClassID);
            return kAudioHardwareNoError;

        case kAudioObjectPropertyName:
            outSize = sizeof(CFStringRef);
            return kAudioHardwareNoError;

        case kAudioObjectPropertyOwner:
            outSize = sizeof(AudioObjectID);
            return kAudioHardwareNoError;

        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyStartingChannel:
            outSize = sizeof(UInt32);
            return kAudioHardwareNoError;

        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            outSize = sizeof(AudioStreamBasicDescription);
            return kAudioHardwareNoError;

        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            // One supported format.
            outSize = sizeof(AudioStreamRangedDescription);
            return kAudioHardwareNoError;

        default:
            outSize = 0;
            return kAudioHardwareUnknownPropertyError;
    }
}

// ===========================================================================
// GetPropertyData
// ===========================================================================

OSStatus stream_get_property_data(const AudioObjectPropertyAddress& addr,
                                  UInt32, const void*,
                                  UInt32 dataSize, UInt32& outUsed, void* outData) noexcept {
    outUsed = 0;
    switch (addr.mSelector) {
        case kAudioObjectPropertyClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioStreamClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyBaseClass: {
            if (dataSize < sizeof(AudioClassID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioClassID*>(outData) = kAudioObjectClassID;
            outUsed = sizeof(AudioClassID);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyName: {
            if (dataSize < sizeof(CFStringRef)) return kAudioHardwareBadPropertySizeError;
            *static_cast<CFStringRef*>(outData) = CFStringCreateWithCString(
                kCFAllocatorDefault, kStreamName, kCFStringEncodingUTF8);
            outUsed = sizeof(CFStringRef);
            return kAudioHardwareNoError;
        }
        case kAudioObjectPropertyOwner: {
            if (dataSize < sizeof(AudioObjectID)) return kAudioHardwareBadPropertySizeError;
            *static_cast<AudioObjectID*>(outData) = kObjectID_Device;
            outUsed = sizeof(AudioObjectID);
            return kAudioHardwareNoError;
        }
        case kAudioStreamPropertyDirection:
            // 1 = input. Our device is input-only.
            return write_u32(1, dataSize, outUsed, outData);
        case kAudioStreamPropertyTerminalType:
            return write_u32(kAudioStreamTerminalTypeMicrophone, dataSize, outUsed, outData);
        case kAudioStreamPropertyIsActive:
            return write_u32(g_stream_active.load(std::memory_order_acquire),
                             dataSize, outUsed, outData);
        case kAudioStreamPropertyLatency:
            // We have no inherent latency beyond the HAL's own buffering;
            // the ring buffer delay is already accounted for in timing.
            return write_u32(0, dataSize, outUsed, outData);
        case kAudioStreamPropertyStartingChannel:
            return write_u32(1, dataSize, outUsed, outData);

        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            if (dataSize < sizeof(AudioStreamBasicDescription)) {
                return kAudioHardwareBadPropertySizeError;
            }
            *static_cast<AudioStreamBasicDescription*>(outData) = make_stream_format();
            outUsed = sizeof(AudioStreamBasicDescription);
            return kAudioHardwareNoError;
        }

        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            if (dataSize < sizeof(AudioStreamRangedDescription)) {
                return kAudioHardwareBadPropertySizeError;
            }
            auto* range = static_cast<AudioStreamRangedDescription*>(outData);
            range->mFormat             = make_stream_format();
            range->mSampleRateRange    = AudioValueRange{ kSampleRate, kSampleRate };
            outUsed = sizeof(AudioStreamRangedDescription);
            return kAudioHardwareNoError;
        }

        default:
            return kAudioHardwareUnknownPropertyError;
    }
}

// ===========================================================================
// SetPropertyData
// ===========================================================================

OSStatus stream_set_property_data(const AudioObjectPropertyAddress& addr,
                                  UInt32, const void*,
                                  UInt32 dataSize, const void* data) noexcept {
    switch (addr.mSelector) {
        case kAudioStreamPropertyIsActive: {
            if (dataSize < sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
            g_stream_active.store(*static_cast<const UInt32*>(data),
                                  std::memory_order_release);
            return kAudioHardwareNoError;
        }
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            if (dataSize < sizeof(AudioStreamBasicDescription)) {
                return kAudioHardwareBadPropertySizeError;
            }
            const auto& requested =
                *static_cast<const AudioStreamBasicDescription*>(data);
            // Accept only our one format. Same-value writes succeed silently.
            if (is_our_format(requested)) {
                return kAudioHardwareNoError;
            }
            return kAudioHardwareIllegalOperationError;
        }
        default:
            return kAudioHardwareUnsupportedOperationError;
    }
}

} // namespace ve_driver

// Common constants and helpers used across the driver.
//
// Centralized so that our device UID, manufacturer, and other string
// identifiers are defined exactly once. These appear in multiple properties
// across the plugin, device, and stream objects — drift is a bug magnet.

#ifndef VOICE_ENHANCER_DRIVER_COMMON_H
#define VOICE_ENHANCER_DRIVER_COMMON_H

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

namespace ve_driver {

// String identifiers. These show up in device pickers and in Console.app log
// lines, so they need to be human-friendly.
inline constexpr const char* kBundleId        = "tech.aheadly.voice-enhancer.driver";
inline constexpr const char* kManufacturer    = "Aheadly Tech";
inline constexpr const char* kDeviceName      = "Voice Enhancer";
inline constexpr const char* kDeviceUID       = "tech.aheadly.voice-enhancer.device";
inline constexpr const char* kStreamName      = "Voice Enhancer Stream";

// Core Audio object IDs. Objects in a HAL plugin have stable numeric IDs
// that we choose. Convention: plugin=1, device=2, stream=3, ...
// Object ID 0 (kAudioObjectUnknown) is reserved.
inline constexpr AudioObjectID kObjectID_Plugin = 1;
inline constexpr AudioObjectID kObjectID_Device = 2;
inline constexpr AudioObjectID kObjectID_Stream = 3;

// Audio format we present.
inline constexpr Float64 kSampleRate      = 48000.0;
inline constexpr UInt32  kChannelsPerFrame = 1;
inline constexpr UInt32  kBitsPerChannel   = 32;          // Float32
inline constexpr UInt32  kBytesPerFrame    = 4;           // sizeof(Float32)
inline constexpr UInt32  kFramesPerPacket  = 1;

} // namespace ve_driver

#endif // VOICE_ENHANCER_DRIVER_COMMON_H

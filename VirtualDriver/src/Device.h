// Device object — represents "Voice Enhancer" as it appears in meeting apps.
//
// The HAL asks this object for its name, its sample rate, how many streams
// it has, what its current configuration is, and so on. Every property the
// HAL knows about maps to one of the `device_*` functions below.

#ifndef VOICE_ENHANCER_DRIVER_DEVICE_H
#define VOICE_ENHANCER_DRIVER_DEVICE_H

#include <CoreAudio/AudioServerPlugIn.h>

namespace ve_driver {

// Property handlers. Returned OSStatus values should use the standard
// kAudioHardware* codes. All functions are safe to call from any thread.

bool     device_has_property           (const AudioObjectPropertyAddress& addr) noexcept;
bool     device_is_property_settable   (const AudioObjectPropertyAddress& addr) noexcept;
OSStatus device_get_property_data_size (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32& outSize) noexcept;
OSStatus device_get_property_data      (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32 dataSize, UInt32& outUsed, void* outData) noexcept;
OSStatus device_set_property_data      (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32 dataSize, const void* data) noexcept;

} // namespace ve_driver

#endif // VOICE_ENHANCER_DRIVER_DEVICE_H

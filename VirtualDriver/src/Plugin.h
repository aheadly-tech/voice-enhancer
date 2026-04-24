// Plugin object — the root of our Core Audio object hierarchy.
//
// The HAL calls us to ask about the plugin itself (its identity, the list of
// devices it owns), then drills into each device. This file exposes the
// AudioServerPlugInDriverInterface vtable pointer that CoreFoundation's
// CFPlugIn mechanism looks for.

#ifndef VOICE_ENHANCER_DRIVER_PLUGIN_H
#define VOICE_ENHANCER_DRIVER_PLUGIN_H

#include <CoreAudio/AudioServerPlugIn.h>

namespace ve_driver {

// Returns the single shared driver ref used by all queries into our plugin.
// Called from the CFPlugIn factory function in Entry.cpp.
AudioServerPlugInDriverRef plugin_interface() noexcept;

// Host reference: set once by Initialize, read anywhere. Thread-safe.
void                     plugin_set_host(AudioServerPlugInHostRef host) noexcept;
AudioServerPlugInHostRef plugin_get_host() noexcept;

// Whether any client is currently running I/O on our device. 1 or 0.
// Bumped by StartIO / StopIO. Read from Device.cpp for the
// kAudioDevicePropertyDeviceIsRunning query.
UInt32 plugin_io_is_running() noexcept;

// Property handlers for the plugin object itself. Implementations live
// in Plugin.cpp; these mirror the HAL's property-query entry points.
bool     plugin_has_property           (const AudioObjectPropertyAddress& addr) noexcept;
bool     plugin_is_property_settable   (const AudioObjectPropertyAddress& addr) noexcept;
OSStatus plugin_get_property_data_size (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32& outSize) noexcept;
OSStatus plugin_get_property_data      (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32 dataSize, UInt32& outUsed, void* outData) noexcept;

} // namespace ve_driver

#endif // VOICE_ENHANCER_DRIVER_PLUGIN_H

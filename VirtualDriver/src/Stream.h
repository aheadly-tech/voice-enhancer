// Stream object — the single input stream owned by our Device.
//
// A device has one or more streams, each representing a logical audio path
// in one direction. For "Voice Enhancer" we expose exactly one input stream
// carrying mono float32 audio at 48 kHz. We do not present an output stream.

#ifndef VOICE_ENHANCER_DRIVER_STREAM_H
#define VOICE_ENHANCER_DRIVER_STREAM_H

#include <CoreAudio/AudioServerPlugIn.h>

namespace ve_driver {

bool     stream_has_property           (const AudioObjectPropertyAddress& addr) noexcept;
bool     stream_is_property_settable   (const AudioObjectPropertyAddress& addr) noexcept;
OSStatus stream_get_property_data_size (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32& outSize) noexcept;
OSStatus stream_get_property_data      (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32 dataSize, UInt32& outUsed, void* outData) noexcept;
OSStatus stream_set_property_data      (const AudioObjectPropertyAddress& addr,
                                        UInt32 qualSize, const void* qual,
                                        UInt32 dataSize, const void* data) noexcept;

} // namespace ve_driver

#endif // VOICE_ENHANCER_DRIVER_STREAM_H

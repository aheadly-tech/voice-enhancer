// Tiny registry mapping AudioObjectID to an object kind.
//
// The HAL plugin interface sends property queries against an AudioObjectID.
// We need to dispatch each query to the right handler. Rather than a tower
// of if/else checks in every property function, we centralize the mapping
// here.

#ifndef VOICE_ENHANCER_DRIVER_OBJECT_REGISTRY_H
#define VOICE_ENHANCER_DRIVER_OBJECT_REGISTRY_H

#include <CoreAudio/AudioServerPlugIn.h>

namespace ve_driver {

enum class ObjectKind {
    Unknown,
    Plugin,
    Device,
    Stream,
};

// Resolve an object ID to its kind. O(1), no allocation.
ObjectKind classify_object(AudioObjectID object_id) noexcept;

} // namespace ve_driver

#endif // VOICE_ENHANCER_DRIVER_OBJECT_REGISTRY_H

#include "ObjectRegistry.h"
#include "Common.h"

namespace ve_driver {

ObjectKind classify_object(AudioObjectID object_id) noexcept {
    switch (object_id) {
        case kObjectID_Plugin: return ObjectKind::Plugin;
        case kObjectID_Device: return ObjectKind::Device;
        case kObjectID_Stream: return ObjectKind::Stream;
        default:               return ObjectKind::Unknown;
    }
}

} // namespace ve_driver

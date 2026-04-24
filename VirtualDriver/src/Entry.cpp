// CFPlugIn entry point.
//
// coreaudiod discovers our bundle via the keys in Info.plist:
//   * CFPlugInTypes lists the type UUID we implement (AudioServerPlugIn).
//   * CFPlugInFactories maps our implementation UUID to the name of the
//     C function below (VoiceEnhancer_Create).
//
// When coreaudiod loads the bundle, it calls the factory function with
// the requested type UUID. We confirm the UUID matches and return a pointer
// to the AudioServerPlugInDriverInterface defined in Plugin.cpp.

#include "Plugin.h"

#include <CoreFoundation/CoreFoundation.h>

// The CFPlugIn machinery resolves this symbol by name (see Info.plist).
// It must be visible in the bundle's dynamic symbol table even when the
// rest of the library is hidden, hence the explicit default visibility.
extern "C" __attribute__((visibility("default")))
void* VoiceEnhancer_Create(CFAllocatorRef /*allocator*/, CFUUIDRef requestedType) {
    // Only serve the AudioServerPlugIn type. Any other UUID is a mismatch
    // and we return null so the CFPlugIn machinery moves on.
    if (!CFEqual(requestedType, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }
    return ve_driver::plugin_interface();
}

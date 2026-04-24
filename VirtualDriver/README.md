# VoiceEnhancer Virtual Driver

A Core Audio Server plugin (HAL plugin) that appears as a microphone in macOS's input device list. Meeting apps (Zoom, Teams, Meet, Discord, OBS) can select it. The Voice Enhancer app feeds it processed audio; the driver presents that audio to any app that reads from it.

## What this is (and isn't)

Apple supports three ways of shipping a custom audio device:

| Approach                 | Kernel extension      | DriverKit (`.dext`)        | Audio Server Plugin (HAL) |
|--------------------------|-----------------------|----------------------------|---------------------------|
| Where it runs            | Kernel space          | User space, restricted     | User space, in `coreaudiod` |
| Status on modern macOS   | Deprecated since 10.15 | Supported but overkill    | **Supported, recommended** |
| What we use              | —                     | —                          | ✓                         |

The artifact is a `.driver` bundle installed at `/Library/Audio/Plug-Ins/HAL/`. The plugin is loaded by the `coreaudiod` daemon and runs in that process — no kernel code, no `.dext` entitlements, no elevated privileges at runtime.

Reference: Apple's [AudioServerPlugIn.h](https://developer.apple.com/documentation/coreaudio/audioserverplugininterface). The definitive (though unofficial) reference implementation is [BlackHole](https://github.com/ExistentialAudio/BlackHole), and this driver's property handling follows the same conventions.

## Architecture

The driver exposes exactly one device with one input stream:

```
AudioServerPlugIn (object 1)
  └── Device  "Voice Enhancer"        (object 2)
        └── Stream  input, mono       (object 3)
              Format: 48 kHz, float32, mono
```

At runtime, the driver and the app communicate through a shared-memory ring buffer described in `../shared/RingBuffer.h`:

```
┌────────────────┐        shared memory ring buffer       ┌────────────────┐
│  VoiceEnhancer │ ──── processed audio ───────────────►  │  coreaudiod    │
│  app           │       (SPSC, lock-free, drop-oldest)   │  (this driver) │
│                │                                        │                │
└────────────────┘                                        │  DoIOOperation │
                                                          │  copies into   │
                                                          │  client buffer │
                                                          └───────┬────────┘
                                                                  │
                                                                  ▼
                                                          Zoom / Teams / etc.
```

The ring is opened lazily on the first I/O cycle so that driver load does not depend on the app being running.

## File layout

```
VirtualDriver/
├── CMakeLists.txt         Bundle target (MH_BUNDLE with .driver extension).
├── Info.plist             CFPlugIn registration: factory UUID + symbol.
├── README.md              This file.
└── src/
    ├── Common.h           Object IDs + constants shared across translation units.
    ├── Entry.cpp          CFPlugIn factory function. Returns the plugin interface.
    ├── Plugin.cpp         AudioServerPlugInDriverInterface: Initialize / Start I/O /
    │                      StopIO / GetZeroTimeStamp / DoIOOperation.
    ├── Plugin.h           Exports the interface pointer + the ring accessor.
    ├── Device.cpp         Device-object property gauntlet.
    ├── Stream.cpp         Stream-object property gauntlet.
    └── ObjectRegistry.cpp Dispatch from HAL object IDs to per-object handlers.
```

Every property a well-behaved HAL client might query is implemented. Missing one is the #1 cause of "device appears, but some app won't use it".

## Building

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build build -j
```

Output: `build/VoiceEnhancer.driver` (a bundle directory).

## Installing

Use the repo-level helper:

```sh
sudo ../scripts/install.sh
```

Or manually:

```sh
sudo cp -R build/VoiceEnhancer.driver /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/VoiceEnhancer.driver
sudo killall coreaudiod    # Reload Core Audio to pick up the plugin.
```

After this the device appears in **System Settings → Sound → Input** and in any app's microphone picker.

## Signing

HAL plugins run inside `coreaudiod` and are checked by Gatekeeper when the daemon loads them. Local-development builds run unsigned on a machine with SIP disabled or with the plugin allow-listed, but any release build must be signed with a Developer ID Application certificate and notarized independently of the app.

See `../scripts/notarize.sh` for the turn-key flow.

## Debugging

HAL plugins are famously awkward to debug because they run in `coreaudiod`, a root daemon. A few things make it tolerable:

- **`log stream --predicate 'subsystem == "tech.aheadly.voice-enhancer"'`** — our `os_log` output surfaces here.
- **`sudo log stream --process coreaudiod`** — coreaudiod's own view. Look for our bundle identifier.
- **`sudo system_profiler SPAudioDataType`** — proves the device is visible to the HAL.
- **`otool -L VoiceEnhancer.driver/Contents/MacOS/VoiceEnhancer`** — sanity-check the link.
- **Attach lldb to coreaudiod** (`sudo lldb -p $(pgrep coreaudiod)`) to set breakpoints. You'll need SIP in the right state and a freshly-killed daemon that's waiting for you to attach.

## Why not just use BlackHole?

A legitimate question. Answers:

- **User experience.** Requiring users to install a separate tool with its own name and UI is confusing. "Voice Enhancer" as the device name is correct; "BlackHole 2ch" is not.
- **Bidirectional control.** Our driver observes the app's liveness via the ring's writer-generation counter and can respond appropriately (silence-pad on underrun rather than stalling).
- **Diagnostic surface.** When something goes wrong, having one piece of software to debug beats two.

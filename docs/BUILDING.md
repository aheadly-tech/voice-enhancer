# Building Voice Enhancer

## TL;DR

```sh
./scripts/build.sh            # Build engine, driver, app.
sudo ./scripts/install.sh     # Install the HAL driver.
```

## Prerequisites

- macOS 13 (Ventura) or later — we use modern Core Audio APIs.
- Xcode 15 or later.
- CMake 3.20+ (`brew install cmake`).
- A Developer ID Application certificate, if you want to ship signed builds. Local development builds run unsigned.

For contributors working on the DSP only: you can build and test `AudioEngine` on any Linux or Unix with a C++17 compiler. The driver and app are macOS-only.

## Components

The project has three independent build artifacts:

1. **`AudioEngine`** — C++17 static library (CMake). No Apple dependencies.
2. **`VirtualDriver`** — HAL plugin `.driver` bundle (CMake).
3. **`VoiceEnhancerApp`** — macOS `.app` bundle (SwiftPM for compile-check, Xcode for the shipping build).

Each has its own `CMakeLists.txt` or `Package.swift`. The top-level driver is `scripts/build.sh`, which stitches them together.

## Build: everything (recommended)

```sh
./scripts/build.sh              # Release build.
./scripts/build.sh --debug      # Debug build, symbols included.
./scripts/build.sh --engine-only
./scripts/build.sh --driver-only
```

Artifacts:

- `AudioEngine/build/libvoice_enhancer.a`
- `AudioEngine/build/voice_enhancer_tests`
- `VirtualDriver/build/VoiceEnhancer.driver`
- `VoiceEnhancerApp/build/Build/Products/Release/Voice Enhancer.app` *(when an Xcode project is present)*

## Build: AudioEngine in isolation

Fastest feedback loop for DSP work — no macOS needed:

```sh
cd AudioEngine
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/voice_enhancer_tests
```

## Build: VirtualDriver

```sh
cd VirtualDriver
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
cmake --build build -j
```

Output: `VirtualDriver/build/VoiceEnhancer.driver` (a bundle directory).

## Build: VoiceEnhancerApp

Two paths:

1. **Shipping build (Xcode project required).**
   Generate the project with `cd VoiceEnhancerApp && xcodegen generate`,
   then open it and build the `VoiceEnhancer` scheme. The project is derived
   from `VoiceEnhancerApp/project.yml` and is not checked into version control.
   CI builds this linked app without signing as well as checking SwiftPM;
   the SwiftPM stub alone does not validate the shipping C/Objective-C bridge.

2. **Compile check (SwiftPM).** macOS only.

    ```sh
    cd VoiceEnhancerApp
    swift build
    ```

   This compiles with a stub engine — the Swift code checks for the `VoiceEnhancerEngine` module and silently falls back to a pass-through if it's absent. Useful for catching SwiftUI regressions in CI without a C++ toolchain configured.

## Audio tap regression checks

Run `cd VoiceEnhancerApp && swift run -c release TapSupportTests` to exercise
tap installation/removal exception handling without microphone permission or
physical audio devices. Both SwiftPM and the shipping app link the same native
helper. The runner covers successful operations, partial installation cleanup,
duplicate taps, missing exception reasons, removal failures and a later success.

For manual acceptance, stop other copies of the app first; this change does not
add a duplicate-instance guard. Confirm capture starts with a compatible input.
A known incompatible 44.1 kHz USB input may still report a tap format error,
but the app must remain running instead of aborting. Device-format conversion
and reconnect recovery require separate fixes and hardware validation.

The native helper uses Objective-C because Swift error handling cannot catch an
`NSException` raised by AVAudioEngine. Failed capture graphs are discarded before
a subsequent start; the sample format and DSP processing path are unchanged.
Device-specific format/reconnect recovery still requires separate fixes and
manual hardware validation. This guard is adapted from wondervip's
[PR #4](https://github.com/aheadly-tech/voice-enhancer/pull/4).

## Install / uninstall

```sh
sudo ./scripts/install.sh     # Copies the driver to /Library/Audio/Plug-Ins/HAL
                              # and restarts coreaudiod.
sudo ./scripts/uninstall.sh   # Removes the bundle, unlinks the shm segment.
```

Both scripts are idempotent — safe to re-run.

## Signing and notarization

Required for public distribution. Not required for local use on your own machine (though macOS will complain the first time).

```sh
./scripts/notarize.sh \
    "VoiceEnhancerApp/build/Build/Products/Release/Voice Enhancer.app" \
    "VirtualDriver/build/VoiceEnhancer.driver"
```

The script uses `xcrun notarytool` with a keychain profile (create once with `xcrun notarytool store-credentials aheadly-notary`). Override the identity and profile via `DEVELOPER_ID` and `NOTARY_PROFILE` env vars.

The HAL driver is a separately-loaded bundle — it must be independently signed and notarized. Gatekeeper checks it when `coreaudiod` loads the plugin.

## Development loop

The fastest iteration cycle for each layer:

- **DSP (C++):** edit → `cmake --build AudioEngine/build && ./AudioEngine/build/voice_enhancer_tests`. Subsecond. Never leave this loop until tests are green.
- **Driver (C++):** edit → `cmake --build VirtualDriver/build` → `sudo ./scripts/install.sh` (which restarts coreaudiod for you). Bundle reload is the slowest step — budget ~3 seconds.
- **UI (Swift):** edit → ⌘R in Xcode. For compile-only checks, `swift build` inside `VoiceEnhancerApp/`.

DSP changes should *never* require changing the Swift side. If they do, the C ABI needs adjustment — update the header comment explaining why.

## Troubleshooting

**"Voice Enhancer" doesn't appear in Zoom/Teams after installing the driver.**
Restart `coreaudiod`: `sudo killall coreaudiod`. Check `Console.app` for errors from `tech.aheadly.voice-enhancer` or `VoiceEnhancer.driver`. Verify the bundle is at `/Library/Audio/Plug-Ins/HAL/VoiceEnhancer.driver` and is owned by `root:wheel`.

**App crashes with `SIGBUS` / `EXC_BAD_ACCESS` in the audio callback.**
Almost always an allocation or lock in `process()`. The audio thread is unforgiving. Run with Instruments' "System Trace" to find the offending call.

**Silence after selecting Voice Enhancer as the mic.**
The app isn't running, or isn't connected to the driver. The driver is a pure consumer — it has nothing to play until the app feeds it. Check that the main window says "Running" in the status pill.

**"Voice Enhancer" shows up but audio is garbled or noisy.**
Check the physical mic and ring format (48 kHz). Capture currently requests a fixed 48 kHz mono tap; incompatible input formats may produce a recoverable tap error. Native-format conversion is separate work. If audio is garbled or noisy, file an issue with the input device details and the output of `Audio MIDI Setup → Voice Enhancer → Format`.

**`install.sh` succeeds but nothing appears.**
The bundle may have been quarantined. Clear the quarantine flag:
```sh
sudo xattr -dr com.apple.quarantine /Library/Audio/Plug-Ins/HAL/VoiceEnhancer.driver
sudo killall coreaudiod
```

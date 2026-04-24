# Architecture

This document explains how Voice Enhancer is structured and, more importantly, *why*. New contributors should read this before making cross-component changes.

## Goals

1. **Real-time safe audio.** The processing callback never allocates, never locks, never blocks. Full stop.
2. **Clean language boundaries.** Swift for UI and AV I/O. C++ for DSP. Core Audio HAL plugin in C++. Communication across the boundary is a narrow C ABI.
3. **Testable DSP.** Every DSP stage is a pure class with deterministic input/output. Audio engine works headless for unit tests.
4. **Swappable components.** The DSP engine does not know there is a UI. The UI does not know there is a virtual driver. Each component can be replaced independently.

## Components

### 1. `AudioEngine/` — the DSP library

Pure C++17, CMake-built static library. No Apple frameworks, no UI, no I/O. Given an input buffer of floats, produces an output buffer of floats.

```
AudioEngine/
├── include/voice_enhancer/   Public headers (what the bridge exposes)
│   ├── Engine.h              Coordinator that holds the DSP chain
│   ├── Preset.h              Preset definitions + lookup
│   ├── Types.h               Common typedefs (SampleRate, FrameCount, etc.)
│   └── dsp/                  Individual DSP stages
│       ├── Biquad.h          Transposed Direct Form II biquad
│       ├── HighPassFilter.h
│       ├── Compressor.h
│       ├── ParametricEQ.h
│       ├── DeEsser.h
│       └── Limiter.h
├── src/                      Implementations (mirror header layout)
├── bridge/                   C ABI for Swift interop
│   ├── engine_c_api.h
│   └── engine_c_api.cpp
└── tests/                    Unit tests (no framework dependency; tiny custom runner)
```

**Contracts:**
- All `process(...)` calls are real-time safe: no `new`, `malloc`, `std::vector::push_back`, `std::mutex`, file I/O, or logging.
- All parameter changes happen via setters that atomically update internal smoothed coefficients. Setters may be called from the UI thread while `process()` runs on the audio thread.
- The engine processes mono float buffers. Stereo is handled by two engine instances, not by interleaved processing. (Simpler and easier to reason about.)

### 2. `VoiceEnhancerApp/` — the macOS app

Swift + SwiftUI. Owns:
- The UI (preset picker, meters, device selection, bypass toggle)
- `AVAudioEngine` setup — mic capture, tap installation, routing to the virtual driver
- The bridge object that wraps the C API as a Swift-friendly type

```
VoiceEnhancerApp/
└── Sources/
    ├── App/                  VoiceEnhancerApp.swift — @main entry point
    ├── Views/                SwiftUI views, one per file
    ├── ViewModels/           ObservableObject types; no UI code inside
    ├── Models/               Plain value types (Preset, Device, etc.)
    ├── Audio/                AVAudioEngine code + C ABI wrapper
    └── Resources/            Assets, Info.plist entitlements
```

**Threading model:**
- UI thread: SwiftUI views, user input, meter updates.
- Audio thread: `AVAudioEngine` render callback. Inside the callback we call the C ABI to process a buffer, then write to the output device.
- Meters are updated by the audio thread writing atomic floats, read by a UI-side `Timer` at ~30 Hz. No locks.

### 3. `VirtualDriver/` — the HAL plugin

A Core Audio Server plugin (a `.driver` bundle installed to `/Library/Audio/Plug-Ins/HAL/`). Appears in other applications' device pickers as "Voice Enhancer". Receives audio from our app via a shared-memory ring buffer (see next section) and exposes it to any client that reads from the device.

This is the hardest piece of the project. See [VirtualDriver/README.md](../VirtualDriver/README.md) for the details specific to this component.

### 4. `shared/RingBuffer.h` — the IPC contract

The app and the driver run in different processes — the app is a normal user process, the driver is loaded into `coreaudiod`. They hand audio off through a single POSIX shared-memory segment mapped into both, laid out as a single-producer / single-consumer lock-free ring:

- Fixed 48 kHz mono float32 format. One ring; one direction (app → driver).
- Power-of-two frame count (currently 4096 — about 85 ms at 48 kHz), so wrap-around is a bitmask instead of a modulus.
- Producer and consumer indices live on separate cache lines to avoid false sharing.
- `shm_open` + `mmap`; no XPC, no privileged helper, no kext. The app writes on its audio thread, the driver reads on its own.
- Overrun policy: drop oldest. A voice path tolerates a small skip far better than stale audio.
- Underrun policy: silence-pad. Better than junk.

The header is `shared/RingBuffer.h`; it includes a full rationale comment block at the top.

## Data flow at runtime

```
Physical mic
     │
     ▼  (48 kHz, mono, float)
AVAudioEngine capture tap
     │
     ▼  (512-sample buffer)
AudioEngineBridge.swift  ──── calls via C ABI ────►  C++ Engine::process()
                                                          │
                                                          ▼
                                                    DSP chain runs:
                                                    HPF → Compressor → EQ
                                                    → DeEsser → Limiter
                                                          │
     ┌────────────────────────────────────────────────────┘
     │
     ▼
Processed buffer written to:
  (a) system output (for monitoring, optional)
  (b) virtual driver's ring buffer (for other apps to read)
```

## Why C ABI for the Swift/C++ bridge?

Swift 5.9+ has direct C++ interop. We *could* import the C++ classes directly into Swift. We intentionally don't, for three reasons:

1. **Stable ABI surface.** The C ABI is easy to version and easy to keep backward-compatible. C++ name-mangling and layout constraints are not.
2. **Lower binding blast radius.** If a C++ header changes internally, the C ABI is unaffected and the Swift side doesn't need to recompile.
3. **Reusable.** A C ABI can be called from Rust, Python (via ctypes), or another Swift project someday. Direct C++ interop locks us to Swift.

The bridge lives in `AudioEngine/bridge/` so it ships with the engine, not with the app.

## Presets live in C++, not Swift

All preset parameter values are defined in `AudioEngine/src/Preset.cpp`. The Swift side only knows the *identifiers* (an enum) and the human-readable names. This keeps the DSP chain self-contained and means you can tune a preset by ear, rebuild the engine, and hear the change without touching the UI.

## Testing strategy

- **DSP unit tests** live in `AudioEngine/tests/`. They feed deterministic buffers (sine sweeps, impulses) through each stage and assert properties (e.g., "HPF attenuates 40 Hz by at least 24 dB").
- **Engine integration tests** verify that the full chain with each preset produces sane output (no NaNs, no infs, no clipping at -1 dBFS input).
- **Manual listening tests** via a `tools/render-file.cpp` CLI that processes a WAV file through a preset. Useful for tuning by ear.

Driver and Swift app are exercised manually and via a small number of XCTest cases.

## What we explicitly do NOT do

- Allocate in `process()`. Ever.
- Use `std::vector::push_back` or `std::string` in the audio thread.
- Call Objective-C from the audio thread (ObjC message send is not RT-safe).
- Log from the audio thread. Meters use atomic floats, not log lines.
- Try to be cross-platform at the DSP layer. It is, accidentally, because it's pure C++. But we don't optimize for it and we don't promise it.

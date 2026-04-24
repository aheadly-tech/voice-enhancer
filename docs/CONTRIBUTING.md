# Contributing

Thanks for your interest in Voice Enhancer. This doc covers the practical bits. Start with [ARCHITECTURE.md](ARCHITECTURE.md) if you haven't — it explains the big "why" that most other questions flow from.

## Ground rules

1. **Don't break the audio thread.** No allocations, no locks, no logging in `process()`. If you're not sure, ask in your PR.
2. **Small PRs.** One change at a time. Reviewers are volunteers.
3. **Match the existing style.** We don't enforce it with a formatter yet but we will soon. Until then: 4-space indent in C++, 4-space in Swift, opening brace on the same line as the function.
4. **Document the why, not the what.** Comments should explain decisions, not restate code.

## Where to put things

| You want to... | Where it goes |
|---|---|
| Tune an existing preset | `AudioEngine/src/Preset.cpp` |
| Add a new preset | Add to the `Preset` enum in `Preset.h`, add values in `Preset.cpp`, add the display name in `VoiceEnhancerApp/Sources/Models/Preset.swift` |
| Add a new DSP stage | New file pair in `AudioEngine/{include,src}/voice_enhancer/dsp/`, add to `Engine` |
| Change the UI | `VoiceEnhancerApp/Sources/Views/` |
| Change the C ABI | `AudioEngine/bridge/engine_c_api.h` + `.cpp`. **This is a public interface.** Keep changes additive. |
| Modify the driver | `VirtualDriver/src/`. Requires the Apple Developer cert for local testing. |

## DSP changes — please include

- The measured effect. Graphs of the frequency response, or a before/after audio file, or a test case that pins behavior. Saying "it sounds better" without evidence gets a kind rejection.
- A test in `AudioEngine/tests/` if the stage is new.
- A note in the PR about CPU impact. Voice Enhancer targets <1% CPU on Apple Silicon.

## UI changes — please include

- A screenshot or short screen recording.
- Confirmation that the change looks right in both light and dark mode.
- Accessibility check: VoiceOver should reach every interactive control and read a sensible label.

## Coding style

### C++

- C++17. We don't use C++20 features yet.
- Smart pointers over raw, always, except in the audio thread where you shouldn't be allocating anyway.
- No exceptions on the audio path. `noexcept` on DSP functions.
- Member variables use `m_` prefix. Free functions are lowercase_snake_case. Types are `PascalCase`.
- Header guards, not `#pragma once`. (Works everywhere, no surprises.)

### Swift

- Swift 5.9+.
- `ObservableObject` view models; never put logic in the view.
- One `View` per file.
- Avoid `@State` for anything shared across views — use `@ObservedObject` or `@EnvironmentObject`.
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

## Filing an issue

Include:
- macOS version
- Mac hardware (Apple Silicon / Intel, model)
- Input device (built-in mic? USB? audio interface?)
- What you expected vs. what happened
- Relevant Console.app output, if any — filter by process name `VoiceEnhancer` or `coreaudiod`

## License

By contributing, you agree that your contributions are licensed under the MIT License (see [../LICENSE](../LICENSE)).

// swift-tools-version:5.9
//
// Swift Package Manager manifest.
//
// This package exists primarily for quick compile checks during development
// (`swift build`). The final shipping artifact is a full .app bundle produced
// by an Xcode project that links against AudioEngine's static library.
//
// Xcode project generation is deferred until the Swift code stabilizes —
// hand-written .xcodeproj churn is noisy and a waste of diff review.

import PackageDescription

let package = Package(
    name: "VoiceEnhancer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoiceEnhancer", targets: ["VoiceEnhancer"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceEnhancer",
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
            // NOTE: When building inside Xcode, the AudioEngine static library
            // is linked via an Xcode build setting. For swift build we stub
            // the engine — see Audio/AudioEngineBridge.swift.
        )
    ]
)

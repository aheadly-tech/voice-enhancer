import Foundation
import CoreAudio

/// A single Core Audio device (input or output), wrapped in a Swift-friendly
/// form that's safe to hand to SwiftUI.
///
/// We intentionally don't expose the raw ``AudioDeviceID`` outside this file's
/// package-private usage site — it's an opaque `UInt32` and leaking it into
/// views invites bugs. The ID lives inside, we identify devices by stable
/// UID strings (which survive unplug/replug) for user-facing purposes.
struct AudioDevice: Identifiable, Hashable {
    /// Core Audio's numeric device ID. Valid only within this boot of the
    /// audio daemon — do NOT persist.
    let deviceID: AudioDeviceID

    /// Device UID. Stable across reboots and unplug/replug of the same
    /// physical device. Safe to persist as the "selected device" preference.
    let uid: String

    /// Human-readable name shown in the device picker.
    let name: String

    /// Whether the device can provide input (microphone capture).
    let hasInput: Bool

    var id: String { uid }
}

import Foundation
import CoreAudio

/// Enumerates Core Audio input devices.
///
/// The HAL's property-address API is verbose and easy to misuse; this type
/// is the single place that deals with it. Everyone else gets back Swift
/// ``AudioDevice`` values.
///
/// Why not use `AVAudioSession`? That's iOS. On macOS we go straight to HAL.
enum AudioDeviceEnumerator {
    private static let virtualDriverName = "Voice Enhancer"

    /// Return every device on the system that can provide input.
    ///
    /// Thread-safe: the underlying HAL calls are safe from any thread and
    /// we do no shared state. Runs in a few hundred microseconds — fine to
    /// call from the main thread during UI refresh.
    static func listInputDevices() -> [AudioDevice] {
        let deviceIDs = allDeviceIDs()
        return deviceIDs.compactMap { id -> AudioDevice? in
            // Skip devices that have zero input channels. We only want mics.
            guard hasInputStreams(deviceID: id) else { return nil }

            guard let uid  = stringProperty(id: id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
            else { return nil }

            return AudioDevice(deviceID: id, uid: uid, name: name, hasInput: true)
        }
    }

    /// Resolve a persisted UID back to a live ``AudioDeviceID``. Returns
    /// nil if the device is no longer present (unplugged, etc.).
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        listInputDevices().first { $0.uid == uid }?.deviceID
    }

    /// The current system-default input device, if one is set.
    static func defaultInputDevice() -> AudioDevice? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &id
        )
        guard status == noErr, id != 0 else { return nil }
        return listInputDevices().first { $0.deviceID == id }
    }

    /// Whether the virtual Voice Enhancer input device is currently visible
    /// to the HAL. This is a better user-facing "driver installed" signal
    /// than shared-memory availability.
    static func hasVoiceEnhancerDriver() -> Bool {
        listInputDevices().contains { $0.name == virtualDriverName }
    }

    // MARK: - Private helpers

    /// Fetch every AudioDeviceID the HAL knows about.
    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size
        )
        guard sizeStatus == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let getStatus = ids.withUnsafeMutableBufferPointer { buf -> OSStatus in
            guard let base = buf.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr, 0, nil, &size, base
            )
        }
        guard getStatus == noErr else { return [] }
        return ids
    }

    /// True if `id` exposes any input stream configuration.
    private static func hasInputStreams(deviceID id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope:    kAudioDevicePropertyScopeInput,
            mElement:  kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 1)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else {
            return false
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        // Any buffer with at least one channel qualifies as an input stream.
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    /// Read a CFString property and bridge it to a Swift string.
    private static func stringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        var cf: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &cf) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr else { return nil }
        return cf as String
    }
}

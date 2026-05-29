import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameVisible),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowBecameVisible(_ notification: Notification) {
        guard isMainAppWindow(notification.object as? NSWindow) else { return }
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard isMainAppWindow(notification.object as? NSWindow) else { return }
        DispatchQueue.main.async {
            if !Self.hasVisibleMainAppWindow() {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func isMainAppWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.title == "Voice Enhancer"
    }

    private static func hasVisibleMainAppWindow() -> Bool {
        NSApp.windows.contains { window in
            window.title == "Voice Enhancer" && window.isVisible && !window.isMiniaturized
        }
    }
}

/// Application entry point.
///
/// This file should remain intentionally small. Anything more than "wire up
/// the scene" goes in ``ContentView`` or deeper. Keeping the @main type
/// trivial makes the app's top-level behavior obvious at a glance and makes
/// it easy to swap in alternative entry points later (e.g. a menu-bar-only
/// mode, a CLI renderer for tuning).
@main
struct VoiceEnhancerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The single shared view model. Injected via environment so any view
    /// that needs audio state can reach it without explicit passing.
    @StateObject private var audio = AudioViewModel()

    var body: some Scene {
        Window("Voice Enhancer", id: "main") {
            ContentView()
                .environmentObject(audio)
                .environment(\.layoutDirection, audio.appLanguage.layoutDirection)
                .frame(minWidth: 520, minHeight: 420)
                .task {
                    // Start the audio graph when the window first appears.
                    // Errors surface into audio.status for the UI to show.
                    await audio.start()
                }
                // NOTE: Do NOT stop audio on window disappear. The user needs
                // the capture graph running while the window is closed (e.g.
                // during a Google Meet call). Audio stops only when the app
                // actually quits (see onReceive below).
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification)
                ) { _ in
                    audio.stop()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarControls()
                .environmentObject(audio)
                .environment(\.layoutDirection, audio.appLanguage.layoutDirection)
        } label: {
            Image(systemName: audio.status.menuBarSystemImage(isEnabled: audio.isEnabled))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(audio.status.menuBarColor(isEnabled: audio.isEnabled))
                .help(audio.status.displayText(language: audio.appLanguage))
        }
    }
}

private struct MenuBarControls: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var audio: AudioViewModel

    var body: some View {
        Label {
            Text(audio.status.displayText(language: audio.appLanguage))
        } icon: {
            Image(systemName: audio.status.menuBarSystemImage(isEnabled: audio.isEnabled))
                .foregroundStyle(audio.status.menuBarColor(isEnabled: audio.isEnabled))
        }

        Divider()

        Button(audio.t(.openApp)) {
            showMainWindow()
        }

        Button(audio.isEnabled ? audio.t(.turnProcessingOff) : audio.t(.turnProcessingOn)) {
            audio.toggleProcessing()
        }

        Button(audio.t(.restartAudioEngine)) {
            audio.reconnectMicrophone()
        }

        Divider()

        Button(audio.t(.quit)) {
            audio.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }
}

private extension AudioViewModel.Status {
    func menuBarSystemImage(isEnabled: Bool) -> String {
        switch self {
        case .failed:
            return "exclamationmark.triangle.fill"
        case .starting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .running:
            return isEnabled ? "waveform.circle.fill" : "waveform.circle"
        case .idle:
            return "power.circle"
        }
    }

    func menuBarColor(isEnabled: Bool) -> Color {
        switch self {
        case .failed:
            return .red
        case .starting:
            return .yellow
        case .running:
            return isEnabled ? .green : .secondary
        case .idle:
            return .secondary
        }
    }
}

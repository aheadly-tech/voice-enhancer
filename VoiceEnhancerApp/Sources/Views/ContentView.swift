import SwiftUI

/// The single-window layout.
///
/// Intentionally flat — this is not a "dashboard". The hierarchy is:
///   1. Header: app name + master on/off toggle + status pill.
///   2. Preset picker: four cards. This is the primary control.
///   3. Meters: compact, live, informative but not flashy.
///   4. Footer: tiny status line for driver health — invisible when things
///      are working, informative when they aren't.
///
/// Deliberately NOT here:
///   * Per-parameter knobs. Presets-only UX in v1.
///   * A menu bar item. Coming in v0.3.
///   * Device picker in the main pane. Device selection lives behind the
///     gear icon — it's a rare, set-once action.
struct ContentView: View {
    @EnvironmentObject private var audio: AudioViewModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 24) {
            HeaderView(showingSettings: $showingSettings)

            PresetPickerView()

            MetersView()

            Spacer(minLength: 0)

            DriverStatusFooter()
        }
        .padding(24)
        .background(WindowBackground())
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @EnvironmentObject private var audio: AudioViewModel
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Enhancer")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                StatusPill(status: audio.status)
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Toggle("", isOn: $audio.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(audio.isEnabled ? "Enhancement on" : "Enhancement bypassed")
        }
    }
}

private struct StatusPill: View {
    let status: AudioViewModel.Status

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var color: Color {
        switch status {
        case .running:  return .green
        case .starting: return .yellow
        case .idle:     return .gray
        case .failed:   return .red
        }
    }
}

// MARK: - Driver status footer

/// Low-key status line at the bottom of the window. When the virtual driver
/// is live, we show nothing — no need to clutter the UI. When it's missing,
/// we surface a compact hint so the user isn't left wondering why the
/// "Voice Enhancer" microphone didn't show up in their meeting app.
private struct DriverStatusFooter: View {
    @EnvironmentObject private var audio: AudioViewModel

    var body: some View {
        Group {
            if audio.driverAvailable {
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    Text("Virtual driver not installed. Run scripts/install.sh to route audio to other apps.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
    }
}

// MARK: - Background

/// Soft gradient background — subtle enough not to compete with content,
/// distinct enough that the app feels deliberately designed.
private struct WindowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor),
                Color(NSColor.windowBackgroundColor).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environmentObject(AudioViewModel())
}

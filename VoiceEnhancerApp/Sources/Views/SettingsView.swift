import SwiftUI

/// Modal settings sheet — secondary configuration.
///
/// Kept behind a gear icon rather than in the main window because:
///   * The main UI is deliberately uncluttered.
///   * Device selection is something you do once, then forget.
///   * Driver status / diagnostics are rarely checked.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audio: AudioViewModel

    /// Local mirror of the selection so the picker binds cleanly even when
    /// the selected device isn't in the list (e.g. unplugged). The "System
    /// Default" sentinel is represented by nil.
    @State private var pickerSelection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

            GroupBox("Input device") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Microphone", selection: $pickerSelection) {
                        Text("System Default").tag(String?.none)
                        ForEach(audio.inputDevices) { device in
                            Text(device.name).tag(Optional(device.uid))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("Voice Enhancer reads from this microphone and publishes the enhanced signal to the virtual input device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Voice tuning") {
                VStack(alignment: .leading, spacing: 14) {
                    // Preview recorder
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            previewControl
                            Spacer()
                        }
                        Text("Record your voice, then adjust sliders to hear changes live.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Voice Leveling")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(Int(audio.compThresholdDb)) dB")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $audio.compThresholdDb, in: -40 ... -10, step: 1)
                        HStack {
                            Text("More")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Less")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Evens out volume differences. Lower values smooth more.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sibilance Reduction")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text("\(Int(audio.deesserThresholdDb)) dB")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $audio.deesserThresholdDb, in: -48 ... -16, step: 1)
                        HStack {
                            Text("More")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("Less")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Reduces harsh \"s\" and \"sh\" sounds.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Virtual driver") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(audio.driverAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.driverAvailable ? "Installed and connected" : "Not connected")
                            .font(.callout.weight(.medium))
                        Text(audio.driverAvailable
                             ? "Select “Voice Enhancer” as the microphone in your meeting app."
                             : "Install the HAL driver with scripts/install.sh to route processed audio to other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice Enhancer")
                        .font(.system(.body, design: .rounded).bold())
                    Text("Open source. MIT licensed.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Link("github.com/aheadly-tech/voice-enhancer",
                         destination: URL(string: "https://github.com/aheadly-tech/voice-enhancer")!)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

                }
                .padding(.top, 12)
            }
        }
        .padding(20)
        .onAppear {
            audio.refreshDeviceList()
            pickerSelection = audio.selectedInputUID
        }
        .onChange(of: pickerSelection) { new in
            if new != audio.selectedInputUID {
                audio.selectedInputUID = new
            }
        }
        .onDisappear {
            audio.stopPreviewPlayback()
        }
    }

    // MARK: - Preview control

    @ViewBuilder
    private var previewControl: some View {
        if case .recording(let countdown) = audio.previewState {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Speak now... \(countdown)s")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if audio.previewState == .recorded {
            HStack(spacing: 8) {
                Button { audio.startPreviewPlayback() } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .controlSize(.small)

                Button { audio.startPreviewRecording() } label: {
                    Label("Re-record", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        } else if audio.previewState == .playing {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Preview playing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button { audio.stopPreviewPlayback() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.small)
            }
        } else {
            Button { audio.startPreviewRecording() } label: {
                Label("Record Test", systemImage: "mic.fill")
            }
            .controlSize(.small)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AudioViewModel())
        .frame(width: 460, height: 520)
}

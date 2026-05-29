import SwiftUI

/// A compact row of tappable preset cards.
///
/// Design notes:
///   * Cards are equally-weighted — we don't promote a "recommended" preset
///     at the UI level. If users wanted a default they'd leave it alone.
///   * The selected card is indicated with a colored ring, not a checkmark.
///     Rings scale better visually with our minimal card layout.
///   * Descriptive text lives below the row so all five presets fit without
///     a horizontal scrollbar, even in the small utility window.
///   * Card tap animates the selection with a spring to give the feel of
///     directly manipulating the audio. Snappy, not bouncy.
struct PresetPickerView: View {
    @EnvironmentObject private var audio: AudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: audio.t(.preset))

            HStack(spacing: 10) {
                ForEach(Preset.allCases) { preset in
                    PresetCardView(
                        preset: preset,
                        isSelected: audio.selectedPreset == preset,
                        language: audio.appLanguage
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            audio.selectedPreset = preset
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: audio.selectedPreset.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)

                    Text(audio.selectedPreset.name(language: audio.appLanguage))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(audio.selectedPreset.blurb(language: audio.appLanguage))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }

                Text(tuningSummary)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.45)
            )
        }
    }

    private var tuningSummary: String {
        "\(audio.t(.voiceLeveling)): \(formatDb(audio.compThresholdDb)) · \(audio.t(.sibilanceReduction)): \(formatDb(audio.deesserThresholdDb))"
    }

    private func formatDb(_ value: Float) -> String {
        "\(Int(value.rounded())) dB"
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview {
    PresetPickerView()
        .environmentObject(AudioViewModel())
        .padding()
        .frame(width: 560)
}
#endif

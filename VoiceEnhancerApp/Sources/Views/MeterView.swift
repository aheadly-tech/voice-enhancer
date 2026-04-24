import SwiftUI

/// The meters panel: input level, output level, compressor GR, de-esser GR.
///
/// Design notes:
///   * Peak meters are scaled logarithmically (-60 dB to 0 dB) because
///     linear peak meters compress the interesting range into a sliver
///     near the top. Log scale matches how we hear.
///   * Gain reduction meters grow from right to left — GR is negative, and
///     "more reduction" visually pulls the bar down.
///   * Smoothing is applied in `AudioViewModel` via a 60 Hz poll with
///     peak-hold ballistics (fast attack, slow release). That keeps the
///     view dumb — just render whatever the view model publishes — and
///     avoids the "freeze during silence" bug that `.onChange`-driven
///     smoothing has.
struct MetersView: View {
    @EnvironmentObject private var audio: AudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Levels")

            VStack(spacing: 8) {
                MeterRow(
                    label: "Input",
                    value: audio.inputPeak,
                    style: .peak
                )
                MeterRow(
                    label: "Output",
                    value: audio.outputPeak,
                    style: .peak
                )
                MeterRow(
                    label: "Comp",
                    value: audio.compressorGrDb,
                    style: .gainReduction
                )
                MeterRow(
                    label: "De-ess",
                    value: audio.deesserGrDb,
                    style: .gainReduction
                )
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

// MARK: - Meter row

private struct MeterRow: View {
    enum Style { case peak, gainReduction }

    let label: String
    let value: Float
    let style: Style

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barGradient)
                        .frame(width: geo.size.width * CGFloat(barFill))
                }
            }
            .frame(height: 8)

            Text(valueText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Scaling

    /// Normalized bar fill in [0, 1].
    private var barFill: Float {
        switch style {
        case .peak:
            // Log scale: -60 dB → 0, 0 dB → 1.
            let safe = max(value, 1e-6)
            let db = 20 * log10(safe)
            let normalized = (db + 60) / 60
            return max(0, min(1, normalized))
        case .gainReduction:
            // Input is negative dB. Map -12 dB → full, 0 dB → empty. 12 dB
            // is the visible top-of-scale: a healthy vocal compressor lives
            // in the 2–6 dB range, so this scale lets normal GR movements
            // actually show up on the bar.
            let gr = max(-12, min(0, value))
            return -gr / 12
        }
    }

    private var valueText: String {
        switch style {
        case .peak:
            let safe = max(value, 1e-6)
            let db = 20 * log10(safe)
            if db <= -59 { return "-∞ dB" }
            return String(format: "%.0f dB", db)
        case .gainReduction:
            // Show one decimal for GR: values are usually small (0–6 dB)
            // and the extra precision reads as "this thing is alive".
            if value > -0.05 { return "0.0 dB" }
            return String(format: "%.1f dB", value)
        }
    }

    private var barGradient: LinearGradient {
        switch style {
        case .peak:
            return LinearGradient(
                colors: [.green, .green, .yellow, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .gainReduction:
            return LinearGradient(
                colors: [.accentColor.opacity(0.7), .accentColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

#Preview {
    MetersView()
        .environmentObject(AudioViewModel())
        .padding()
        .frame(width: 520)
}

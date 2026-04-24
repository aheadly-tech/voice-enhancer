import SwiftUI

/// A single preset card: icon, name, short blurb.
///
/// Selected state is shown with a colored ring. Un-selected state uses the
/// standard material fill so the cards recede visually until focused. Hover
/// and press animations are subtle — audio apps aren't games, and we don't
/// want cards vying for attention.
struct PresetCardView: View {
    let preset: Preset
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: preset.systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(height: 28)

            Text(preset.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(preset.blurb)
                .font(.system(size: 10, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding(.horizontal, 8)
        .background(background)
        .overlay(border)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(preset.name)
        .accessibilityHint(preset.blurb)
    }

    // MARK: - Styling

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .opacity(isSelected ? 1.0 : (isHovering ? 0.9 : 0.7))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                isSelected
                    ? Color.accentColor.opacity(0.9)
                    : Color.primary.opacity(isHovering ? 0.12 : 0.06),
                lineWidth: isSelected ? 1.5 : 1
            )
    }
}

#Preview {
    HStack {
        PresetCardView(preset: .natural, isSelected: true)
        PresetCardView(preset: .broadcast, isSelected: false)
    }
    .padding()
    .frame(width: 400)
}

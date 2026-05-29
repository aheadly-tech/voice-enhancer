import SwiftUI

/// A compact preset card: icon and name.
///
/// Selected state is shown with a colored ring. Un-selected state uses the
/// standard material fill so the cards recede visually until focused. Hover
/// and press animations are subtle — audio apps aren't games, and we don't
/// want cards vying for attention. The longer preset description is shown
/// below the row by PresetPickerView.
struct PresetCardView: View {
    let preset: Preset
    let isSelected: Bool
    let language: AppLanguage

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: preset.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(height: 24)

            Text(preset.name(language: language))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .padding(.horizontal, 6)
        .background(background)
        .overlay(border)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(preset.name(language: language))
        .accessibilityHint(preset.blurb(language: language))
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

#if DEBUG
#Preview {
    HStack {
        PresetCardView(preset: .natural, isSelected: true, language: .english)
        PresetCardView(preset: .broadcast, isSelected: false, language: .english)
    }
    .padding()
    .frame(width: 400)
}
#endif

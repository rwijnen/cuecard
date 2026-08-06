import SwiftUI

/// Shared between Settings and the setup wizard: two cards showing what each style looks
/// like, because "notification or notch" means little as a plain radio pair.
struct StylePicker: View {
    @Binding var selection: PresentationStyle

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PresentationStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    card(style)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == style ? [.isSelected] : [])
            }
        }
    }

    private func card(_ style: PresentationStyle) -> some View {
        let selected = selection == style
        return VStack(spacing: 8) {
            sketch(style)
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            VStack(spacing: 2) {
                Text(style.title).font(.system(size: 12, weight: .semibold))
                Text(style.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: selected ? 1.5 : 1)
        )
    }

    /// A miniature of the screen with the card in place — enough to tell the two apart.
    private func sketch(_ style: PresentationStyle) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .padding(6)

                switch style {
                case .notification:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: width * 0.4, height: 20)
                        .padding(.top, 12)
                        .padding(.trailing, 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                case .notch:
                    VStack(spacing: 0) {
                        // The notch itself.
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.75))
                            .frame(width: width * 0.2, height: 7)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: width * 0.44, height: 18)
                            .padding(.top, 1)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

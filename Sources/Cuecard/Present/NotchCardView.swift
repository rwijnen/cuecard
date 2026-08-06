import SwiftUI

/// Sizes for the notch card. Measured values come from `NSScreen` at present time, so a
/// card on an external display is laid out for that display.
struct NotchCardMetrics: Equatable {
    var cardWidth: CGFloat = 428
    /// Sized to the content: artwork row, the up-next line, and the padding around them.
    /// Any more and the card has a dead strip along the bottom.
    var bodyHeight: CGFloat = 92
    /// Height of the region the system reserves at the top of the display — the physical
    /// notch. Zero on displays without one.
    var notchStripHeight: CGFloat = 0
    /// Breathing room between the menu bar and the top of the card. Without it the card is
    /// tangent to the menu bar and the rounded corners look like a mistake.
    var topGap: CGFloat = 6
    /// Width of the notch, when it could be measured.
    var notchWidth: CGFloat?

    var totalHeight: CGFloat { notchStripHeight + topGap + bodyHeight }
    /// Everything above the card body is transparent, and clicks there must pass through
    /// to the menu bar.
    var transparentTopHeight: CGFloat { notchStripHeight + topGap }
    var hasNotch: Bool { notchStripHeight > 0 }
}

/// Mutable content for the card, so the window and its hosting view survive between
/// tracks and only the text and artwork change.
@MainActor
final class NotchCardModel: ObservableObject {
    @Published var cue: Cue?
    @Published var metrics = NotchCardMetrics()
    /// Drives the slide-out animation. Set after the window is on screen so the card is
    /// seen to emerge from the notch rather than appearing already out.
    @Published var revealed = false

    /// Forces the opaque background instead of vibrancy, independently of the system's
    /// Reduce Transparency setting. `NSVisualEffectView` cannot be rasterised by
    /// `ImageRenderer`, so this is how the card is rendered offscreen for inspection.
    @Published var opaqueBackground = false

    var onSkip: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onActivateSpotify: () -> Void = {}
}

struct NotchCardView: View {
    @ObservedObject var model: NotchCardModel

    /// System-wide Reduce Transparency. When it is on, macOS expects vibrancy to be
    /// replaced by an opaque fill rather than merely dimmed.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Artwork edge and the gap after it — the up-next line is indented by this so it
    /// lines up with the title rather than sitting under the cover.
    private static let artworkSize: CGFloat = 46
    private static let artworkGap: CGFloat = 11
    private static let cornerRadius: CGFloat = 22

    var body: some View {
        let metrics = model.metrics
        VStack(spacing: 0) {
            // The physical notch and the gap below it. Nothing may be drawn across the full
            // width here or the card would cover the menu bar to either side.
            Spacer(minLength: 0).frame(height: metrics.transparentTopHeight)
            card(metrics)
        }
        .frame(width: metrics.cardWidth, height: metrics.totalHeight, alignment: .top)
        // Slide up out of sight when retracted; the window is only briefly this tall.
        .offset(y: model.revealed ? 0 : -metrics.totalHeight)
        .opacity(model.revealed ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.revealed)
    }

    private func card(_ metrics: NotchCardMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(width: metrics.cardWidth, height: metrics.bodyHeight, alignment: .top)
            .background {
                ZStack {
                    if reduceTransparency || model.opaqueBackground {
                        Color(red: 0.07, green: 0.08, blue: 0.08)
                    } else {
                        VisualEffectBackground()
                        // The blur alone is not enough: over a bright wallpaper the white
                        // text loses contrast. A gentle top-down scrim fixes that without
                        // turning the card back into a flat panel.
                        LinearGradient(
                            colors: [.black.opacity(0.42), .black.opacity(0.24)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .clipShape(shape)
                .overlay {
                    // A bright hairline on top and a darker one below reads as a lit edge,
                    // which is what keeps a translucent panel from looking like a hole.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                }
                // The window itself draws no shadow — it would trace the full rectangle,
                // transparent notch strip included.
                .shadow(color: .black.opacity(0.34), radius: 14, y: 6)
            }
            .onHover { model.onHover($0) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Self.artworkGap) {
                artwork
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.cue?.track.title ?? "Nothing playing")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(model.cue?.track.artist ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
                // Tapping the text or artwork brings Spotify forward; the button below
                // is the only control, so the rest of the card can be a single target.
                .contentShape(Rectangle())
                .onTapGesture { model.onActivateSpotify() }

                Spacer(minLength: 6)
                skipButton
            }
            upNext
        }
        // Text over a live blur needs its own shadow to stay readable when the wallpaper
        // behind it is busy.
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }

    private var artwork: some View {
        Group {
            if let image = model.cue?.artworkImage {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    Color.white.opacity(0.10)
                    Image(systemName: "music.note")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        }
    }

    private var skipButton: some View {
        Button(action: model.onSkip) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Next track")
        .accessibilityLabel("Next track")
    }

    @ViewBuilder
    private var upNext: some View {
        if let next = model.cue?.next {
            HStack(spacing: 5) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 9, weight: .semibold))
                Text("Up next")
                    .font(.system(size: 10, weight: .semibold))
                Text(next.oneLine)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.58))
            .padding(.leading, Self.artworkSize + Self.artworkGap)
        }
    }
}

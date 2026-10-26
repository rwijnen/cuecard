import AppKit
import SwiftUI

/// The top of the status item's menu: the cover, with title, artist and album beside it.
///
/// A plain `NSMenuItem` can carry a 16-point image at most, which is no use for album art,
/// so this is a SwiftUI view hosted in the item. Clicking it brings Spotify forward, like
/// clicking the notch card does.
struct NowPlayingMenuHeader: View {
    let track: Track
    let artwork: NSImage?
    let isPaused: Bool
    var onActivate: () -> Void = {}

    /// Wide enough for a typical title on two lines; the menu takes its width from the
    /// widest item, so this also sets the menu's width.
    static let width: CGFloat = 300
    private static let artworkSize: CGFloat = 64
    /// Menus on macOS 26 have generously rounded corners, and a square cover inside one
    /// looks cut out of it rather than placed on it.
    private static let artworkCornerRadius: CGFloat = 10

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                if isPaused {
                    Text("Paused")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let album = track.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens Spotify")
    }

    private var cover: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.high)
            } else {
                ZStack {
                    Color.primary.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.artworkCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.artworkCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

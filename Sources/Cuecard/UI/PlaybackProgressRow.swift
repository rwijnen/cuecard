import SwiftUI

/// The track's length on the left, a bar, and the time left counting down on the right:
/// `3:45 ━━━━━━━──── −2:10`.
///
/// Ticks once a second from the last sample rather than asking Spotify, which is polled
/// only every few seconds. Paused progress stands still.
struct PlaybackProgressRow: View {
    let progress: PlaybackProgress
    var fontSize: CGFloat = 9.5
    /// Colour of the two times.
    var labelStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    /// Colour of the played part of the bar; the rest is a faint version of it.
    var barStyle: AnyShapeStyle = AnyShapeStyle(.primary)

    static let barHeight: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: progress.sampledAt, by: 1)) { context in
            row(at: context.date)
        }
    }

    private func row(at date: Date) -> some View {
        HStack(spacing: 7) {
            Text(PlaybackProgress.format(progress.duration))
                .foregroundStyle(labelStyle)
            bar(fraction: progress.fraction(at: date))
            // A true minus sign: a hyphen sits too low beside digits.
            Text("\u{2212}" + PlaybackProgress.format(progress.remaining(at: date)))
                .foregroundStyle(labelStyle)
        }
        // Tabular digits, or the row shuffles sideways every second as 1s and 0s swap.
        .font(.system(size: fontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(PlaybackProgress.format(progress.remaining(at: date))) left of "
                + PlaybackProgress.format(progress.duration)
        )
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(barStyle).opacity(0.22)
                Capsule()
                    .fill(barStyle)
                    .frame(width: max(Self.barHeight, proxy.size.width * fraction))
                    // Nothing played yet: no dot of fill at the start.
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: Self.barHeight)
    }
}

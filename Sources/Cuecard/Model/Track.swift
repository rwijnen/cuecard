import Foundation

/// One track, as much as we know about it. Fields beyond `id`/`title`/`artist` are
/// optional because they arrive from three sources of differing generosity: the
/// distributed notification Spotify broadcasts, an AppleScript query, and the Web API.
struct Track: Equatable, Sendable {
    /// Spotify URI, e.g. `spotify:track:4cOdK2wGLETKBW3PvgPWqT`. Empty for local files
    /// that Spotify has not given an identity.
    var id: String
    var title: String
    var artist: String
    var album: String?
    /// Total length. Spotify reports milliseconds; we normalise to seconds on the way in.
    var duration: TimeInterval?
    var artworkURL: URL?

    init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
    }

    /// The one-line form used for the "up next" line and the menu bar.
    var oneLine: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }

    /// Identity for change detection. Prefer the Spotify URI, but local files and
    /// podcasts sometimes arrive without one, so fall back to the text.
    var identity: String {
        id.isEmpty ? "\(title)\u{1F}\(artist)\u{1F}\(album ?? "")" : id
    }
}

enum PlayerState: String, Equatable, Sendable {
    case playing
    case paused
    case stopped
    /// Spotify is not running at all.
    case notRunning
}

/// What we believe is going on right now.
struct PlaybackSnapshot: Equatable, Sendable {
    var state: PlayerState
    var track: Track?
    /// Seconds into the track.
    var position: TimeInterval?

    static let idle = PlaybackSnapshot(state: .notRunning, track: nil, position: nil)

    init(state: PlayerState, track: Track? = nil, position: TimeInterval? = nil) {
        self.state = state
        self.track = track
        self.position = position
    }
}

/// How far into a track playback is, as of one sample. Spotify is asked every few seconds,
/// not every second, so views extrapolate from the sample to tick between polls.
struct PlaybackProgress: Equatable, Sendable {
    /// The `Track.identity` this was sampled for, so a view never pairs one track's
    /// position with another's title.
    var trackIdentity: String
    var duration: TimeInterval
    var position: TimeInterval
    var sampledAt: Date
    /// Paused progress stands still; playing progress runs on from `sampledAt`.
    var isPlaying: Bool

    /// Seconds into the track at `date`. Clamped to the track, because between the end of
    /// one track and the broadcast for the next, a running clock would overshoot.
    func elapsed(at date: Date) -> TimeInterval {
        let running = isPlaying ? max(0, date.timeIntervalSince(sampledAt)) : 0
        return min(max(0, position + running), duration)
    }

    /// Whole seconds left, counted as the total less the whole seconds played. That way
    /// the countdown starts on exactly the total shown beside it and reaches `0:00` when
    /// the track ends, rather than one of the two being a second out from rounding.
    func remaining(at date: Date) -> TimeInterval {
        (duration.rounded(.down) - elapsed(at: date).rounded(.down)).clamped(to: 0...duration)
    }

    /// 0...1, for the bar.
    func fraction(at date: Date) -> Double {
        duration > 0 ? elapsed(at: date) / duration : 0
    }

    /// What to show for `track`: the latest sample if it belongs to that track, otherwise
    /// the track standing at its start. `nil` when the length is unknown — some local
    /// files and podcast episodes arrive without one — since a bar needs an end.
    static func forDisplay(of track: Track, latest: PlaybackProgress?, now: Date = Date()) -> PlaybackProgress? {
        if let latest, latest.trackIdentity == track.identity, latest.duration > 0 { return latest }
        guard let duration = track.duration, duration > 0 else { return nil }
        return PlaybackProgress(
            trackIdentity: track.identity,
            duration: duration,
            position: 0,
            sampledAt: now,
            isPlaying: false
        )
    }

    /// `3:07`, or `1:02:03` past the hour. Rounded down, as players do.
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

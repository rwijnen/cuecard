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

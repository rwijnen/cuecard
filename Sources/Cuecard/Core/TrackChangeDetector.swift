import Foundation

/// Decides whether a snapshot is worth interrupting the user for.
///
/// This matters more than it sounds: Spotify broadcasts a playback change on pause,
/// resume, seek and volume-adjacent events too, and the backup poller re-reports the
/// same track every few seconds. Without this filter you would get a notification storm.
/// Kept as a pure value type so every rule below is directly testable.
struct TrackChangeDetector {
    /// Un-pausing the track you were already on: news, or not?
    var notifyOnResume: Bool

    /// A track whose position falls back to (roughly) the start while its identity stays
    /// put has been replayed — Spotify's repeat-one, or a manual seek home.
    var replayRewindThreshold: TimeInterval = 3

    /// Floor between two announcements of the *same* track, so a jittery position or a
    /// double broadcast cannot produce a pair of notifications.
    var minimumRepeatInterval: TimeInterval = 5

    private var lastAnnouncedIdentity: String?
    private var lastAnnouncedAt: Date = .distantPast
    private var lastState: PlayerState = .notRunning
    private var lastPosition: TimeInterval = 0

    init(notifyOnResume: Bool = false) {
        self.notifyOnResume = notifyOnResume
    }

    /// Records a snapshot without announcing it. Used for whatever is already playing
    /// when the app starts: you launched Cuecard, you know what is on.
    mutating func prime(_ snapshot: PlaybackSnapshot) {
        lastState = snapshot.state
        lastPosition = snapshot.position ?? 0
        if snapshot.state == .playing, let track = snapshot.track {
            lastAnnouncedIdentity = track.identity
            lastAnnouncedAt = .distantPast
        }
    }

    /// Returns the track to announce, or `nil` to stay quiet.
    mutating func evaluate(_ snapshot: PlaybackSnapshot, now: Date = Date()) -> Track? {
        let previousState = lastState
        let previousPosition = lastPosition
        lastState = snapshot.state
        lastPosition = snapshot.position ?? 0

        guard snapshot.state == .playing, let track = snapshot.track else { return nil }

        if track.identity == lastAnnouncedIdentity {
            let position = snapshot.position ?? 0
            let replayed = position <= replayRewindThreshold && previousPosition > replayRewindThreshold
            let resumed = previousState == .paused && notifyOnResume
            guard replayed || resumed,
                  now.timeIntervalSince(lastAnnouncedAt) >= minimumRepeatInterval
            else { return nil }
        }

        lastAnnouncedIdentity = track.identity
        lastAnnouncedAt = now
        return track
    }

    /// Forgets what has been announced, so the next snapshot is treated as new. Used
    /// after the presentation style changes, where re-showing the card is the point.
    mutating func reset() {
        lastAnnouncedIdentity = nil
        lastAnnouncedAt = .distantPast
    }
}

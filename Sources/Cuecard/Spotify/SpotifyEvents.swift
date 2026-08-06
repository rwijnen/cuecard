import AppKit
import Foundation

/// Spotify broadcasts a distributed notification every time playback changes, and it
/// carries the whole track in `userInfo`. That is our primary trigger: it is instant,
/// costs nothing, and — unlike AppleScript — needs no Automation permission.
///
/// It omits the artwork URL and knows nothing about the queue, so `NowPlayingMonitor`
/// enriches what arrives here. A slow timer backs it up in case a broadcast is missed.
enum SpotifyEvents {
    static let bundleIdentifier = "com.spotify.client"
    static let playbackChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")

    /// Keys Spotify puts in `userInfo`. Capitalised and spaced, exactly as sent.
    private enum Key {
        static let state = "Player State"
        static let trackID = "Track ID"
        static let name = "Name"
        static let artist = "Artist"
        static let album = "Album"
        static let duration = "Duration"
        static let position = "Playback Position"
    }

    /// Turns one broadcast's `userInfo` into a snapshot. Pure, so it can be tested
    /// against real captured payloads.
    ///
    /// Returns `nil` only when the payload has no usable player state at all — a
    /// malformed broadcast we should ignore rather than act on.
    static func snapshot(from userInfo: [AnyHashable: Any]) -> PlaybackSnapshot? {
        guard let raw = userInfo[Key.state] as? String else { return nil }

        let state: PlayerState
        switch raw.lowercased() {
        case "playing": state = .playing
        case "paused": state = .paused
        case "stopped": state = .stopped
        default: return nil
        }

        let title = userInfo[Key.name] as? String ?? ""
        let artist = userInfo[Key.artist] as? String ?? ""
        let id = userInfo[Key.trackID] as? String ?? ""

        // Stopped, or a payload with nothing identifying in it, means there is no track
        // to talk about. Don't invent an empty one.
        guard state != .stopped, !(title.isEmpty && id.isEmpty) else {
            return PlaybackSnapshot(state: state, track: nil, position: nil)
        }

        let track = Track(
            id: id,
            title: title,
            artist: artist,
            album: (userInfo[Key.album] as? String).flatMap { $0.isEmpty ? nil : $0 },
            // Spotify sends milliseconds here, seconds in `Playback Position`.
            duration: (userInfo[Key.duration] as? NSNumber).map { $0.doubleValue / 1000 }
        )

        return PlaybackSnapshot(
            state: state,
            track: track,
            position: (userInfo[Key.position] as? NSNumber)?.doubleValue
        )
    }

    /// Whether the Spotify desktop app is running. Checked before every AppleScript call
    /// so we never wake Spotify up just to ask it a question.
    static var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// Wraps the distributed-notification subscription so the monitor can own it as a value.
final class SpotifyEventObserver {
    private var token: NSObjectProtocol?
    private let center = DistributedNotificationCenter.default()

    /// `handler` is called on the main queue for every broadcast we can parse.
    func start(_ handler: @escaping (PlaybackSnapshot) -> Void) {
        guard token == nil else { return }
        token = center.addObserver(
            forName: SpotifyEvents.playbackChanged,
            object: nil,
            queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let snapshot = SpotifyEvents.snapshot(from: info)
            else {
                Log.spotify.debug("ignoring unparseable playback broadcast")
                return
            }
            handler(snapshot)
        }
        Log.spotify.info("listening for Spotify playback broadcasts")
    }

    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }

    deinit { stop() }
}

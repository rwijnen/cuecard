import Foundation

/// Async wrappers for the AppleScript bridge.
///
/// `SpotifyScripting` spawns and waits on a child process, so none of it may run on the
/// main thread — a wedged Spotify would freeze the menu bar. These hop to a background
/// queue and swallow failures, because every caller's fallback is simply "do without".
extension SpotifyScripting {
    static func artworkURLAsync() async -> URL? {
        await offMainThread { (try? artworkURL()) ?? nil }
    }

    static func snapshotAsync() async -> PlaybackSnapshot {
        await offMainThread { (try? snapshot()) ?? PlaybackSnapshot(state: .notRunning) }
    }

    /// Fire and forget: the resulting playback change arrives as a broadcast, so there is
    /// nothing to wait for.
    static func nextTrackAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try nextTrack()
            } catch {
                Log.spotify.error("skip failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func offMainThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

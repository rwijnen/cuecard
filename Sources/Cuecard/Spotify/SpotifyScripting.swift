import Foundation

/// Talks to the Spotify desktop app over Apple Events.
///
/// Two jobs only: fetch the artwork URL (the distributed notification leaves it out) and
/// skip to the next track. Both are cheap and neither is on the hot path — detection is
/// push-based, see `SpotifyEvents`.
///
/// Runs `osascript` in a child process rather than using `NSAppleScript`, which is not
/// thread-safe and cannot be given a hard deadline. A child process can be killed if
/// Spotify wedges, which keeps a hung music player from taking the app with it.
enum SpotifyScripting {

    enum Failure: Error, Equatable {
        case notRunning
        case timedOut
        /// osascript exited non-zero — usually the user declined the Automation prompt.
        case scriptFailed(status: Int32, message: String)
    }

    /// Separator for the delimited record the snapshot script returns: ASCII unit
    /// separator, which cannot occur in a track title.
    private static let fieldSeparator: Character = "\u{1F}"

    // MARK: - Commands

    /// Everything the local app knows about what is playing, artwork URL included.
    static func snapshot() throws -> PlaybackSnapshot {
        guard SpotifyEvents.spotifyIsRunning else { throw Failure.notRunning }
        return parseSnapshot(try run(snapshotScript))
    }

    /// Just the artwork URL for whatever is playing now. Used to fill in the one field
    /// the broadcast omits, so it stays a single round trip per track change.
    static func artworkURL() throws -> URL? {
        guard SpotifyEvents.spotifyIsRunning else { throw Failure.notRunning }
        let text = try run(artworkScript)
        return text.isEmpty ? nil : URL(string: text)
    }

    static func nextTrack() throws {
        guard SpotifyEvents.spotifyIsRunning else { throw Failure.notRunning }
        _ = try run(#"tell application "Spotify" to next track"#)
    }

    static func previousTrack() throws {
        guard SpotifyEvents.spotifyIsRunning else { throw Failure.notRunning }
        _ = try run(#"tell application "Spotify" to previous track"#)
    }

    // MARK: - Parsing

    /// Splits the delimited record the snapshot script produces. Pure, so the field
    /// order and the locale quirks below are covered by tests.
    static func parseSnapshot(_ raw: String) -> PlaybackSnapshot {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch text {
        case "notrunning": return PlaybackSnapshot(state: .notRunning)
        case "stopped": return PlaybackSnapshot(state: .stopped)
        default: break
        }

        let fields = text.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        // state, id, name, artist, album, duration, position, artwork
        guard fields.count >= 7 else { return PlaybackSnapshot(state: .stopped) }

        let state: PlayerState = fields[0] == "playing" ? .playing : .paused
        let track = Track(
            id: fields[1],
            title: fields[2],
            artist: fields[3],
            album: fields[4].isEmpty ? nil : fields[4],
            // Spotify's `duration` is milliseconds.
            duration: number(fields[5]).map { $0 / 1000 },
            artworkURL: fields.count > 7 && !fields[7].isEmpty ? URL(string: fields[7]) : nil
        )
        return PlaybackSnapshot(state: state, track: track, position: number(fields[6]))
    }

    /// AppleScript renders reals with the *user's* decimal separator, so a Dutch or
    /// German system hands back `12,345`. Accept either.
    private static func number(_ field: String) -> Double? {
        Double(field.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Scripts

    /// `is running` is deliberate: unlike most commands it does not launch the app.
    /// The Swift side checks `NSRunningApplication` first anyway, so this is belt and
    /// braces against Spotify quitting between the check and the event.
    /// Variable names are spelled out deliberately. AppleScript reserves some very short
    /// identifiers — `st` is the ordinal suffix from "1st" and fails to parse as a
    /// variable at all — and inside a `tell` block a bare word like `position` can bind
    /// to an application property instead.
    private static let snapshotScript = """
    set sep to (character id 31)
    if application "Spotify" is not running then return "notrunning"
    tell application "Spotify"
        with timeout of 10 seconds
            set playerStatus to (player state as text)
            if playerStatus is "stopped" then return "stopped"
            set theTrack to current track
            set artURL to ""
            try
                set artURL to (artwork url of theTrack)
            end try
            set elapsed to 0
            try
                set elapsed to (player position)
            end try
            return playerStatus & sep & (id of theTrack) & sep & (name of theTrack) ¬
                & sep & (artist of theTrack) & sep & (album of theTrack) ¬
                & sep & ((duration of theTrack) as text) ¬
                & sep & (elapsed as text) & sep & artURL
        end timeout
    end tell
    """

    private static let artworkScript = """
    if application "Spotify" is not running then return ""
    tell application "Spotify"
        with timeout of 10 seconds
            try
                return (artwork url of current track)
            on error
                return ""
            end try
        end timeout
    end tell
    """

    // MARK: - Process

    /// Warm, these calls take about 0.2s. The generous default is for the first event
    /// after Spotify launches, which has been measured to exceed two seconds — the
    /// timeout that was here originally, which made the first snapshot after a cold start
    /// fail every time. Always called off the main thread, so a long wait costs nothing
    /// but a late card.
    private static func run(_ source: String, timeout: TimeInterval = 12) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw Failure.scriptFailed(status: -1, message: error.localizedDescription)
        }

        // A wedged Spotify would otherwise leave osascript blocked on the Apple Event
        // past its own `with timeout`. Kill the child instead of waiting.
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        // Drain before waiting: a full pipe buffer would deadlock the child.
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let timedOut = killer.isCancelled == false && process.terminationReason == .uncaughtSignal
        killer.cancel()

        guard process.terminationStatus == 0 else {
            if timedOut { throw Failure.timedOut }
            let message = String(decoding: err)
            Log.spotify.error("osascript failed (\(process.terminationStatus)): \(message, privacy: .public)")
            throw Failure.scriptFailed(status: process.terminationStatus, message: message)
        }
        return String(decoding: out).trimmingCharacters(in: .newlines)
    }
}

private extension String {
    init(decoding data: Data) {
        self = String(data: data, encoding: .utf8) ?? ""
    }
}

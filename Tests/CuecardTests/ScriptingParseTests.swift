import Foundation
import Testing

@testable import Cuecard

@Suite("AppleScript record parsing")
struct ScriptingParseTests {
    private let separator = "\u{1F}"

    private func record(_ fields: String...) -> String {
        fields.joined(separator: separator)
    }

    @Test("a full record is parsed")
    func fullRecord() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing",
            "spotify:track:67Hna13dNDkZvBpTXRIaOJ",
            "Teardrop",
            "Massive Attack",
            "Mezzanine",
            "330000",
            "12.5",
            "https://i.scdn.co/image/abc123"
        ))
        #expect(snapshot.state == .playing)
        let track = try #require(snapshot.track)
        #expect(track.title == "Teardrop")
        #expect(track.artist == "Massive Attack")
        #expect(track.album == "Mezzanine")
        #expect(track.duration == 330)
        #expect(track.artworkURL?.absoluteString == "https://i.scdn.co/image/abc123")
        #expect(snapshot.position == 12.5)
    }

    @Test("the sentinel replies are recognised")
    func sentinels() {
        #expect(SpotifyScripting.parseSnapshot("notrunning").state == .notRunning)
        #expect(SpotifyScripting.parseSnapshot("stopped").state == .stopped)
        // osascript appends a newline.
        #expect(SpotifyScripting.parseSnapshot("notrunning\n").state == .notRunning)
    }

    /// AppleScript formats reals with the *user's* decimal separator, so this is what a
    /// Dutch or German system hands back. Getting it wrong silently broke repeat-one
    /// detection, since the position always parsed as nil.
    @Test("a comma decimal separator is accepted")
    func localisedDecimals() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing", "spotify:track:x", "A", "B", "C", "330000", "12,5", ""
        ))
        #expect(snapshot.position == 12.5)
    }

    @Test("an empty artwork field yields no URL rather than a bad one")
    func emptyArtwork() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing", "spotify:track:x", "A", "B", "C", "1000", "0", ""
        ))
        #expect(try #require(snapshot.track).artworkURL == nil)
    }

    @Test("a record with the artwork field absent entirely still parses")
    func truncatedRecord() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing", "spotify:track:x", "A", "B", "C", "1000", "0"
        ))
        #expect(snapshot.track?.title == "A")
        #expect(snapshot.track?.artworkURL == nil)
    }

    @Test("a record too short to trust is treated as stopped")
    func malformedRecord() {
        #expect(SpotifyScripting.parseSnapshot(record("playing", "x", "A")).state == .stopped)
        #expect(SpotifyScripting.parseSnapshot("").state == .stopped)
    }

    @Test("paused is distinguished from playing")
    func pausedState() {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "paused", "spotify:track:x", "A", "B", "C", "1000", "0", ""
        ))
        #expect(snapshot.state == .paused)
    }

    /// Titles carrying em dashes, quotes and — the awkward one — the separator's near
    /// neighbours must survive. The unit separator itself cannot occur in a title, which
    /// is why it was chosen over a tab.
    @Test("punctuation in titles survives the split")
    func awkwardTitles() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing", "spotify:track:x",
            #"Everything In Its Right Place — "Live""#,
            "Radiohead\tand friends",
            "Kid A", "1000", "0", ""
        ))
        let track = try #require(snapshot.track)
        #expect(track.title == #"Everything In Its Right Place — "Live""#)
        #expect(track.artist == "Radiohead\tand friends")
    }

    @Test("an empty album field becomes nil")
    func emptyAlbum() throws {
        let snapshot = SpotifyScripting.parseSnapshot(record(
            "playing", "spotify:track:x", "A", "B", "", "1000", "0", ""
        ))
        #expect(try #require(snapshot.track).album == nil)
    }
}

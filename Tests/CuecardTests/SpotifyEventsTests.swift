import Foundation
import Testing

@testable import Cuecard

/// Payloads below match what Spotify actually broadcasts, keys and capitalisation
/// included — the parser is only as good as those strings staying right.
@Suite("Playback broadcast parsing")
struct SpotifyEventsTests {
    private let playing: [AnyHashable: Any] = [
        "Player State": "Playing",
        "Track ID": "spotify:track:67Hna13dNDkZvBpTXRIaOJ",
        "Name": "Teardrop",
        "Artist": "Massive Attack",
        "Album": "Mezzanine",
        "Album Artist": "Massive Attack",
        "Disc Number": 1,
        "Duration": 330_000,
        "Playback Position": 12.5,
        "Popularity": 71,
        "Has Artwork": true,
    ]

    @Test("a playing broadcast becomes a full snapshot")
    func playingSnapshot() throws {
        let snapshot = try #require(SpotifyEvents.snapshot(from: playing))
        #expect(snapshot.state == .playing)
        #expect(snapshot.track?.title == "Teardrop")
        #expect(snapshot.track?.artist == "Massive Attack")
        #expect(snapshot.track?.album == "Mezzanine")
        #expect(snapshot.position == 12.5)
    }

    @Test("duration is converted from milliseconds to seconds")
    func durationInSeconds() throws {
        let snapshot = try #require(SpotifyEvents.snapshot(from: playing))
        #expect(snapshot.track?.duration == 330)
    }

    @Test("paused is recognised and keeps its track")
    func paused() throws {
        var info = playing
        info["Player State"] = "Paused"
        let snapshot = try #require(SpotifyEvents.snapshot(from: info))
        #expect(snapshot.state == .paused)
        #expect(snapshot.track != nil)
    }

    @Test("stopped carries no track")
    func stopped() throws {
        var info = playing
        info["Player State"] = "Stopped"
        let snapshot = try #require(SpotifyEvents.snapshot(from: info))
        #expect(snapshot.state == .stopped)
        #expect(snapshot.track == nil)
    }

    @Test("a payload with no player state is rejected rather than guessed at")
    func missingState() {
        #expect(SpotifyEvents.snapshot(from: ["Name": "Teardrop"]) == nil)
        #expect(SpotifyEvents.snapshot(from: ["Player State": "Rewinding"]) == nil)
    }

    @Test("a payload with nothing identifying produces no track")
    func emptyTrack() throws {
        let snapshot = try #require(SpotifyEvents.snapshot(from: ["Player State": "Playing"]))
        #expect(snapshot.state == .playing)
        #expect(snapshot.track == nil)
    }

    @Test("missing optional fields do not lose the track")
    func sparsePayload() throws {
        let snapshot = try #require(SpotifyEvents.snapshot(from: [
            "Player State": "Playing",
            "Track ID": "spotify:track:x",
            "Name": "Untitled",
        ]))
        #expect(snapshot.track?.title == "Untitled")
        #expect(snapshot.track?.artist == "")
        #expect(snapshot.track?.album == nil)
        #expect(snapshot.track?.duration == nil)
    }

    @Test("an empty album string does not become an empty subtitle")
    func emptyAlbumIsNil() throws {
        var info = playing
        info["Album"] = ""
        let snapshot = try #require(SpotifyEvents.snapshot(from: info))
        #expect(snapshot.track?.album == nil)
    }

    @Test("state is matched case-insensitively")
    func caseInsensitiveState() throws {
        var info = playing
        info["Player State"] = "PLAYING"
        #expect(try #require(SpotifyEvents.snapshot(from: info)).state == .playing)
    }
}

@Suite("Track identity")
struct TrackIdentityTests {
    @Test("the Spotify URI is the identity when present")
    func uriWins() {
        let track = Track(id: "spotify:track:abc", title: "A", artist: "B")
        #expect(track.identity == "spotify:track:abc")
    }

    @Test("without a URI, identity falls back to the text")
    func textFallback() {
        let a = Track(id: "", title: "A", artist: "B", album: "C")
        let b = Track(id: "", title: "A", artist: "B", album: "C")
        let c = Track(id: "", title: "A", artist: "B", album: "D")
        #expect(a.identity == b.identity)
        #expect(a.identity != c.identity)
    }

    @Test("matching prefers IDs but tolerates their absence")
    func matching() {
        #expect(Track(id: "x", title: "A", artist: "B").matches(Track(id: "x", title: "Z", artist: "Y")))
        #expect(!Track(id: "x", title: "A", artist: "B").matches(Track(id: "y", title: "A", artist: "B")))
        // One side without an ID: compare what a person would compare, case-insensitively.
        #expect(Track(id: "", title: "Teardrop", artist: "Massive Attack")
            .matches(Track(id: "x", title: "teardrop", artist: "massive attack")))
    }

    @Test("the one-line form omits a missing artist rather than dangling a dash")
    func oneLine() {
        #expect(Track(id: "x", title: "A", artist: "B").oneLine == "A — B")
        #expect(Track(id: "x", title: "A", artist: "").oneLine == "A")
    }
}

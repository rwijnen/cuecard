import Foundation
import Testing

@testable import Cuecard

/// The filter that stands between Spotify's chatter and your notification centre. Every
/// rule here corresponds to a way the app was observed to be annoying.
@Suite("Track change detection")
struct TrackChangeDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(
        _ state: PlayerState,
        id: String = "spotify:track:a",
        title: String = "A",
        position: TimeInterval = 0
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            state: state,
            track: state == .stopped || state == .notRunning
                ? nil
                : Track(id: id, title: title, artist: "Artist"),
            position: position
        )
    }

    @Test("a new track is announced")
    func newTrack() {
        var detector = TrackChangeDetector()
        #expect(detector.evaluate(snapshot(.playing), now: t0)?.title == "A")
    }

    @Test("the same track is not announced twice")
    func duplicateSuppressed() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, position: 0), now: t0)
        // The backup poll re-reports the same track a second later.
        let again = detector.evaluate(snapshot(.playing, position: 1), now: t0.addingTimeInterval(1))
        #expect(again == nil)
    }

    @Test("a different track is announced")
    func changeAnnounced() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, id: "a", title: "A"), now: t0)
        let next = detector.evaluate(
            snapshot(.playing, id: "b", title: "B"),
            now: t0.addingTimeInterval(200)
        )
        #expect(next?.title == "B")
    }

    @Test("pausing and resuming stays quiet by default")
    func resumeQuiet() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, position: 10), now: t0)
        _ = detector.evaluate(snapshot(.paused, position: 30), now: t0.addingTimeInterval(20))
        let resumed = detector.evaluate(snapshot(.playing, position: 30), now: t0.addingTimeInterval(60))
        #expect(resumed == nil)
    }

    @Test("resuming is announced when the user asked for it")
    func resumeOptedIn() {
        var detector = TrackChangeDetector(notifyOnResume: true)
        _ = detector.evaluate(snapshot(.playing, position: 10), now: t0)
        _ = detector.evaluate(snapshot(.paused, position: 30), now: t0.addingTimeInterval(20))
        let resumed = detector.evaluate(snapshot(.playing, position: 30), now: t0.addingTimeInterval(60))
        #expect(resumed?.title == "A")
    }

    @Test("repeat-one is announced when the track restarts")
    func replayAnnounced() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, position: 2), now: t0)
        // Play through to near the end, then wrap around to the start.
        _ = detector.evaluate(snapshot(.playing, position: 200), now: t0.addingTimeInterval(198))
        let replayed = detector.evaluate(snapshot(.playing, position: 0.4), now: t0.addingTimeInterval(215))
        #expect(replayed?.title == "A")
    }

    @Test("a replay within the repeat floor is suppressed")
    func replayThrottled() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, position: 4), now: t0)
        // A position that jitters back below the threshold immediately must not fire.
        let jitter = detector.evaluate(snapshot(.playing, position: 0.2), now: t0.addingTimeInterval(1))
        #expect(jitter == nil)
    }

    @Test("nothing is announced while paused or stopped")
    func silentWhenNotPlaying() {
        var detector = TrackChangeDetector()
        #expect(detector.evaluate(snapshot(.paused), now: t0) == nil)
        #expect(detector.evaluate(snapshot(.stopped), now: t0) == nil)
        #expect(detector.evaluate(snapshot(.notRunning), now: t0) == nil)
    }

    @Test("whatever is already playing at launch is not announced")
    func primingIsSilent() {
        var detector = TrackChangeDetector()
        detector.prime(snapshot(.playing, position: 42))
        let same = detector.evaluate(snapshot(.playing, position: 43), now: t0)
        #expect(same == nil)
    }

    @Test("priming still lets the next track through")
    func primingDoesNotBlockNext() {
        var detector = TrackChangeDetector()
        detector.prime(snapshot(.playing, id: "a", position: 42))
        let next = detector.evaluate(snapshot(.playing, id: "b", title: "B"), now: t0)
        #expect(next?.title == "B")
    }

    @Test("reset makes the current track announceable again")
    func resetReannounces() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(snapshot(.playing, position: 5), now: t0)
        detector.reset()
        let again = detector.evaluate(snapshot(.playing, position: 6), now: t0.addingTimeInterval(1))
        #expect(again?.title == "A")
    }

    @Test("tracks without an ID are told apart by title and artist")
    func identityFallsBackToText() {
        var detector = TrackChangeDetector()
        _ = detector.evaluate(
            PlaybackSnapshot(state: .playing, track: Track(id: "", title: "Local A", artist: "X"), position: 0),
            now: t0
        )
        let other = detector.evaluate(
            PlaybackSnapshot(state: .playing, track: Track(id: "", title: "Local B", artist: "X"), position: 0),
            now: t0.addingTimeInterval(10)
        )
        #expect(other?.title == "Local B")
    }
}

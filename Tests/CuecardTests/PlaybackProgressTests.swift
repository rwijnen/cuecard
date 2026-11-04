import Foundation
import Testing

@testable import Cuecard

/// The clock behind the progress bar: it runs between Spotify's samples, and the two
/// times beside the bar have to agree with each other and with the end of the track.
@Suite("Playback progress")
struct PlaybackProgressTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func progress(position: TimeInterval, duration: TimeInterval = 200, playing: Bool = true) -> PlaybackProgress {
        PlaybackProgress(
            trackIdentity: "spotify:track:a",
            duration: duration,
            position: position,
            sampledAt: t0,
            isPlaying: playing
        )
    }

    @Test("playing progress runs on from the sample")
    func extrapolates() {
        #expect(progress(position: 10).elapsed(at: t0.addingTimeInterval(5)) == 15)
    }

    @Test("paused progress stands still")
    func pausedStill() {
        #expect(progress(position: 10, playing: false).elapsed(at: t0.addingTimeInterval(60)) == 10)
    }

    @Test("the clock stops at the end of the track")
    func clampsAtEnd() {
        let late = t0.addingTimeInterval(500)
        #expect(progress(position: 190).elapsed(at: late) == 200)
        #expect(progress(position: 190).remaining(at: late) == 0)
        #expect(progress(position: 190).fraction(at: late) == 1)
    }

    @Test("the countdown starts on the total and ends on zero")
    func countdownMatchesTotal() {
        let p = progress(position: 0, duration: 200.7)
        #expect(PlaybackProgress.format(p.remaining(at: t0)) == PlaybackProgress.format(p.duration))
        #expect(p.remaining(at: t0.addingTimeInterval(200.2)) == 0)
    }

    @Test("times format as players show them")
    func formatting() {
        #expect(PlaybackProgress.format(0) == "0:00")
        #expect(PlaybackProgress.format(65.9) == "1:05")
        #expect(PlaybackProgress.format(600) == "10:00")
        #expect(PlaybackProgress.format(3723) == "1:02:03")
    }

    @Test("a sample for another track is not shown")
    func otherTrackIgnored() {
        let track = Track(id: "spotify:track:b", title: "B", artist: "X", duration: 120)
        let shown = PlaybackProgress.forDisplay(of: track, latest: progress(position: 50), now: t0)
        #expect(shown?.trackIdentity == "spotify:track:b")
        #expect(shown?.position == 0)
        #expect(shown?.duration == 120)
    }

    @Test("a track of unknown length has no bar")
    func unknownLength() {
        let track = Track(id: "spotify:track:b", title: "B", artist: "X")
        #expect(PlaybackProgress.forDisplay(of: track, latest: nil) == nil)
    }
}

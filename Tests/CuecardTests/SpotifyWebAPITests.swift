import Foundation
import Testing

@testable import Cuecard

/// JSON below is shaped like real `GET /v1/me/player/queue` responses, trimmed to the
/// fields the app reads.
@Suite("Queue decoding")
struct SpotifyWebAPITests {
    private func json(_ string: String) -> Data { Data(string.utf8) }

    @Test("a normal queue decodes to a current track and its successors")
    func normalQueue() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {
          "currently_playing": {
            "id": "67Hna13dNDkZvBpTXRIaOJ",
            "uri": "spotify:track:67Hna13dNDkZvBpTXRIaOJ",
            "name": "Teardrop",
            "duration_ms": 330000,
            "type": "track",
            "artists": [{"name": "Massive Attack"}],
            "album": {
              "name": "Mezzanine",
              "images": [
                {"url": "https://i.scdn.co/image/big", "width": 640, "height": 640},
                {"url": "https://i.scdn.co/image/mid", "width": 300, "height": 300},
                {"url": "https://i.scdn.co/image/small", "width": 64, "height": 64}
              ]
            }
          },
          "queue": [
            {"uri": "spotify:track:b", "name": "Inertia Creeps",
             "artists": [{"name": "Massive Attack"}], "album": {"name": "Mezzanine"}},
            {"uri": "spotify:track:c", "name": "Angel",
             "artists": [{"name": "Massive Attack"}], "album": {"name": "Mezzanine"}}
          ]
        }
        """))

        #expect(queue.current?.title == "Teardrop")
        #expect(queue.current?.duration == 330)
        #expect(queue.current?.id == "spotify:track:67Hna13dNDkZvBpTXRIaOJ")
        #expect(queue.upcoming.count == 2)
        #expect(queue.upcoming.first?.oneLine == "Inertia Creeps — Massive Attack")
    }

    /// A notification thumbnail is around 40 points, so the 640px cover is wasted
    /// bandwidth. Smallest-at-least-300 is the sweet spot.
    @Test("artwork picks the smallest image still large enough")
    func artworkSelection() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"currently_playing": {"name": "A", "album": {"images": [
          {"url": "https://x/640", "width": 640},
          {"url": "https://x/300", "width": 300},
          {"url": "https://x/64", "width": 64}
        ]}}, "queue": []}
        """))
        #expect(queue.current?.artworkURL?.absoluteString == "https://x/300")
    }

    @Test("when every image is small the largest is used")
    func artworkFallsBackToLargest() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"currently_playing": {"name": "A", "album": {"images": [
          {"url": "https://x/64", "width": 64},
          {"url": "https://x/160", "width": 160}
        ]}}, "queue": []}
        """))
        #expect(queue.current?.artworkURL?.absoluteString == "https://x/160")
    }

    /// Podcast episodes come back with a `show` and no `artists`, which used to decode
    /// into a track with an empty artist line.
    @Test("a podcast episode in the queue is usable")
    func podcastEpisode() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {
          "currently_playing": {"uri": "spotify:track:a", "name": "Teardrop",
            "artists": [{"name": "Massive Attack"}], "album": {"name": "Mezzanine"}},
          "queue": [
            {"uri": "spotify:episode:e1", "name": "Episode 42", "type": "episode",
             "duration_ms": 3600000, "show": {"name": "Some Podcast"}}
          ]
        }
        """))
        let episode = try #require(queue.upcoming.first)
        #expect(episode.title == "Episode 42")
        #expect(episode.artist == "Some Podcast")
        #expect(episode.album == "Some Podcast")
    }

    @Test("multiple artists are joined")
    func multipleArtists() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"currently_playing": {"name": "Collab",
          "artists": [{"name": "A"}, {"name": "B"}], "album": {"name": "X"}}, "queue": []}
        """))
        #expect(queue.current?.artist == "A, B")
    }

    @Test("nothing playing decodes to an empty queue")
    func nothingPlaying() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json(#"{"currently_playing": null, "queue": []}"#))
        #expect(queue.current == nil)
        #expect(queue.upcoming.isEmpty)
    }

    @Test("absent keys decode rather than throw")
    func sparsePayload() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("{}"))
        #expect(queue.current == nil)
        #expect(queue.upcoming.isEmpty)
    }

    /// A nameless item is not worth showing and would render as a blank up-next line, so
    /// it is dropped rather than passed through.
    @Test("unnameable queue items are dropped")
    func namelessItemsDropped() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"queue": [{"uri": "spotify:track:a"}, {"uri": "spotify:track:b", "name": "Real"}]}
        """))
        #expect(queue.upcoming.count == 1)
        #expect(queue.upcoming.first?.title == "Real")
    }

    @Test("an album with no images yields no artwork URL")
    func noImages() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"currently_playing": {"name": "A", "album": {"name": "X", "images": []}}, "queue": []}
        """))
        #expect(queue.current?.artworkURL == nil)
    }

    @Test("an item with only an id, no uri, still has an identity")
    func idWithoutURI() throws {
        let queue = try SpotifyWebAPI.decodeQueue(json("""
        {"currently_playing": {"id": "abc", "name": "A"}, "queue": []}
        """))
        #expect(queue.current?.id == "abc")
    }
}

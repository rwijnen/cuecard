import Foundation

/// The queue endpoint, and nothing else.
///
/// `GET /v1/me/player/queue` is the only way to learn what plays next: the desktop app's
/// AppleScript dictionary exposes the current track and nothing beyond it. The same
/// response also carries full-size album art, so when this is available it supplies both
/// and saves an Apple Event.
@MainActor
final class SpotifyWebAPI {
    struct Queue: Equatable, Sendable {
        var current: Track?
        var upcoming: [Track]
    }

    private let auth: SpotifyAuth
    private let session: URLSession

    init(auth: SpotifyAuth, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    var isAvailable: Bool { auth.isConnected }

    func queue() async throws -> Queue {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/queue")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        switch http.statusCode {
        case 200:
            // Nothing playing on any device returns 204 with no body; 200 with an empty
            // body has also been observed, so treat unparseable-but-OK as empty.
            guard !data.isEmpty else { return Queue(current: nil, upcoming: []) }
            return try Self.decodeQueue(data)
        case 204:
            return Queue(current: nil, upcoming: [])
        case 401:
            throw Failure.unauthorized
        case 403:
            throw Failure.forbidden
        case 429:
            throw Failure.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        default:
            throw Failure.http(status: http.statusCode)
        }
    }

    enum Failure: LocalizedError, Equatable {
        case badResponse
        case unauthorized
        case forbidden
        case rateLimited(retryAfter: Double?)
        case http(status: Int)

        var errorDescription: String? {
            switch self {
            case .badResponse: "Spotify sent a response we could not read."
            case .unauthorized: "Spotify rejected the access token."
            case .forbidden: "Spotify refused the request. Check the app's scopes."
            case .rateLimited: "Spotify is rate limiting us."
            case .http(let status): "Spotify returned HTTP \(status)."
            }
        }
    }

    // MARK: - Decoding

    /// Kept `nonisolated` so tests can feed it captured JSON without a main-actor hop.
    nonisolated static func decodeQueue(_ data: Data) throws -> Queue {
        let payload = try JSONDecoder().decode(QueuePayload.self, from: data)
        return Queue(
            current: payload.currentlyPlaying?.track,
            upcoming: payload.queue?.compactMap(\.track) ?? []
        )
    }

    /// Queue items are not always songs: podcast episodes come back with a `show`
    /// instead of an `album` and no `artists` at all, so every field past the name is
    /// optional and the two shapes are flattened into one `Track`.
    private struct QueuePayload: Decodable {
        let currentlyPlaying: Item?
        let queue: [Item]?

        enum CodingKeys: String, CodingKey {
            case currentlyPlaying = "currently_playing"
            case queue
        }

        struct Item: Decodable {
            let id: String?
            let uri: String?
            let name: String?
            let durationMs: Double?
            let artists: [Named]?
            let album: Album?
            let show: Named?

            enum CodingKeys: String, CodingKey {
                case id, uri, name, artists, album, show
                case durationMs = "duration_ms"
            }

            var track: Track? {
                guard let name, !name.isEmpty else { return nil }
                let artist = artists?.compactMap(\.name).joined(separator: ", ")
                return Track(
                    id: uri ?? id ?? "",
                    title: name,
                    artist: (artist?.isEmpty == false ? artist : show?.name) ?? "",
                    album: album?.name ?? show?.name,
                    duration: durationMs.map { $0 / 1000 },
                    artworkURL: album?.bestArtwork
                )
            }
        }

        struct Named: Decodable {
            let name: String?
        }

        struct Album: Decodable {
            let name: String?
            let images: [Image]?

            /// Spotify sorts images widest first, but that is convention, not contract.
            /// A notification thumbnail is small, so prefer the smallest image at least
            /// 300px wide and only fall back to the largest.
            var bestArtwork: URL? {
                guard let images, !images.isEmpty else { return nil }
                let sized = images.compactMap { image -> (Int, URL)? in
                    guard let url = image.url.flatMap(URL.init(string:)) else { return nil }
                    return (image.width ?? 0, url)
                }
                guard !sized.isEmpty else { return nil }
                let big = sized.filter { $0.0 >= 300 }.min { $0.0 < $1.0 }
                return (big ?? sized.max { $0.0 < $1.0 })?.1
            }
        }

        struct Image: Decodable {
            let url: String?
            let width: Int?
        }
    }
}

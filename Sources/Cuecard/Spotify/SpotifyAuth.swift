import AppKit
import Combine
import Foundation

/// Holds the Spotify Web API connection: sign-in, token refresh, sign-out.
///
/// The Web API is needed for exactly one thing — the queue, so we can say what plays
/// next. Everything else comes from the local app. If this is never connected the app
/// still works; it just has nothing to put on the last line.
@MainActor
final class SpotifyAuth: ObservableObject {
    /// The queue endpoint is all we call, so this is the only scope we ask for. No
    /// `user-modify-playback-state`: skipping goes through the local app, which needs no
    /// scope and no Premium subscription.
    static let scope = "user-read-playback-state"

    enum Failure: LocalizedError {
        case noClientID
        case denied
        case mismatchedState
        case tokenExchange(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .noClientID:
                "No Spotify client ID has been set."
            case .denied:
                "Spotify sign-in was declined."
            case .mismatchedState:
                "The sign-in response did not match this request and was ignored."
            case .tokenExchange(let detail):
                "Spotify rejected the sign-in: \(detail)"
            case .notConnected:
                "Not signed in to Spotify."
            }
        }
    }

    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false

    private let preferences: Preferences
    private let session: URLSession
    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var refreshToken: String? {
        didSet { recomputeConnected() }
    }

    init(preferences: Preferences, session: URLSession = .shared) {
        self.preferences = preferences
        self.session = session
        // Property observers do not run during initialisation, so the subscription below
        // — which fires immediately with the current value — is what sets `isConnected`.
        self.refreshToken = SecretStore.load()

        // The client ID lives in UserDefaults and the refresh token in the Keychain, and
        // the two can drift apart: clearing preferences leaves the token orphaned. A token
        // without its client ID cannot be refreshed, so treating that as connected made
        // every track log a failed queue lookup.
        preferences.$clientID
            .sink { [weak self] clientID in self?.recomputeConnected(clientID: clientID) }
            .store(in: &cancellables)
    }

    /// Both halves are needed, which is why this is not just a nil check. `nonisolated` so
    /// the rule is directly testable.
    nonisolated static func isUsable(refreshToken: String?, clientID: String) -> Bool {
        refreshToken?.isEmpty == false
            && !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func recomputeConnected(clientID: String? = nil) {
        // `@Published` emits in `willSet`, so the value has to come from the publisher
        // rather than by reading `preferences.clientID` back.
        isConnected = Self.isUsable(
            refreshToken: refreshToken,
            clientID: clientID ?? preferences.clientID
        )
    }

    // MARK: - Sign in / out

    func connect() async throws {
        let clientID = preferences.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw Failure.noClientID }

        isConnecting = true
        defer { isConnecting = false }

        let verifier = PKCE.verifier()
        let expectedState = PKCE.state()
        let receiver = LoopbackReceiver()

        var authorize = URLComponents(string: "https://accounts.spotify.com/authorize")!
        authorize.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: LoopbackReceiver.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "state", value: expectedState),
            .init(name: "scope", value: Self.scope),
        ]

        // Start listening before the browser opens, or a fast redirect races the listener.
        async let callback = receiver.awaitCallback()
        NSWorkspace.shared.open(authorize.url!)
        let items = try await callback

        if let error = items["error"] {
            throw error == "access_denied" ? Failure.denied : Failure.tokenExchange(error)
        }
        guard items["state"] == expectedState else { throw Failure.mismatchedState }
        guard let code = items["code"] else { throw Failure.tokenExchange("no authorization code") }

        try await exchange(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": LoopbackReceiver.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        Log.auth.info("connected to the Spotify Web API")
    }

    func disconnect() {
        accessToken = nil
        accessTokenExpiry = .distantPast
        refreshToken = nil
        SecretStore.clear()
        Log.auth.info("disconnected from the Spotify Web API")
    }

    // MARK: - Tokens

    /// A usable access token, refreshing if the cached one is spent.
    func validAccessToken() async throws -> String {
        // Refresh a minute early rather than discover expiry mid-request.
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) {
            return accessToken
        }
        guard let refreshToken else { throw Failure.notConnected }
        let clientID = preferences.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw Failure.noClientID }

        try await exchange(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
        guard let accessToken else { throw Failure.notConnected }
        return accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private func exchange(form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.encode(form).utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            // A rejected refresh token is permanently dead — usually the user revoked
            // access. Clear it so the UI offers a fresh sign-in instead of retrying.
            if form["grant_type"] == "refresh_token" { disconnect() }
            throw Failure.tokenExchange(detail)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(token.expiresIn)
        // Spotify rotates refresh tokens; a response without one means keep the old.
        if let rotated = token.refreshToken {
            refreshToken = rotated
            SecretStore.save(rotated)
        } else if refreshToken == nil {
            Log.auth.error("token response carried no refresh token")
        }
    }

    /// `nonisolated`: a pure transform with nothing to do with the actor, and directly
    /// testable this way.
    nonisolated static func encode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}

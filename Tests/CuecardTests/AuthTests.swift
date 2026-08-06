import Foundation
import Testing

@testable import Cuecard

@Suite("PKCE")
struct PKCETests {
    /// The worked example from RFC 7636 Appendix B. If this fails, Spotify will reject
    /// every sign-in with `invalid_grant`, so it is the one case worth pinning exactly.
    @Test("the RFC 7636 test vector round-trips")
    func rfcVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("challenges carry no base64 padding or URL-unsafe characters")
    func base64URLSafety() {
        for _ in 0..<50 {
            let challenge = PKCE.challenge(for: PKCE.verifier())
            #expect(!challenge.contains("="))
            #expect(!challenge.contains("+"))
            #expect(!challenge.contains("/"))
        }
    }

    @Test("verifiers use only unreserved characters")
    func verifierAlphabet() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<50 {
            #expect(PKCE.verifier().allSatisfy(allowed.contains))
        }
    }

    @Test("verifier length is honoured and within spec")
    func verifierLength() {
        #expect(PKCE.verifier().count == 64)
        #expect(PKCE.verifier(length: 43).count == 43)
        #expect(PKCE.verifier(length: 128).count == 128)
    }

    @Test("verifiers and states do not repeat")
    func uniqueness() {
        #expect(Set((0..<64).map { _ in PKCE.verifier() }).count == 64)
        #expect(Set((0..<64).map { _ in PKCE.state() }).count == 64)
    }
}

@Suite("Token request encoding")
struct FormEncodingTests {
    /// A code verifier contains `~`, `-`, `.` and `_`, all of which must survive
    /// unescaped, and a refresh token can contain `+` and `/`, which must not.
    @Test("unreserved characters pass through, everything else is escaped")
    func escaping() {
        let encoded = SpotifyAuth.encode(["code_verifier": "abc-._~XYZ", "token": "a+b/c=d"])
        #expect(encoded.contains("code_verifier=abc-._~XYZ"))
        #expect(encoded.contains("token=a%2Bb%2Fc%3Dd"))
    }

    @Test("pairs are joined with ampersands in a stable order")
    func ordering() {
        #expect(SpotifyAuth.encode(["b": "2", "a": "1", "c": "3"]) == "a=1&b=2&c=3")
    }

    @Test("an empty form encodes to an empty body")
    func empty() {
        #expect(SpotifyAuth.encode([:]) == "")
    }
}

@Suite("Connection state")
struct ConnectionStateTests {
    /// The client ID lives in UserDefaults and the refresh token in the Keychain, so the
    /// two can drift apart — clearing preferences orphans the token. A token that cannot
    /// be refreshed is not a connection, and treating it as one made every track change
    /// attempt a queue lookup and log a failure.
    @Test("both halves are required")
    func bothHalvesRequired() {
        #expect(SpotifyAuth.isUsable(refreshToken: "AQD-token", clientID: "abc123"))
        #expect(!SpotifyAuth.isUsable(refreshToken: "AQD-token", clientID: ""))
        #expect(!SpotifyAuth.isUsable(refreshToken: nil, clientID: "abc123"))
        #expect(!SpotifyAuth.isUsable(refreshToken: nil, clientID: ""))
    }

    @Test("a whitespace-only client ID does not count")
    func whitespaceClientID() {
        #expect(!SpotifyAuth.isUsable(refreshToken: "AQD-token", clientID: "   "))
        #expect(!SpotifyAuth.isUsable(refreshToken: "AQD-token", clientID: "\n\t "))
    }

    @Test("an empty stored token does not count")
    func emptyToken() {
        #expect(!SpotifyAuth.isUsable(refreshToken: "", clientID: "abc123"))
    }
}

@Suite("OAuth callback parsing")
struct LoopbackReceiverTests {
    @Test("the request target is taken from the request line")
    func requestTarget() {
        let request = "GET /callback?code=abc&state=xyz HTTP/1.1\r\nHost: 127.0.0.1:8888\r\n\r\n"
        #expect(LoopbackReceiver.requestTarget(request) == "/callback?code=abc&state=xyz")
    }

    /// Browsers fetch `/favicon.ico` alongside the redirect; those must not be mistaken
    /// for the callback.
    @Test("non-GET and other paths are still reported for the caller to filter")
    func otherRequests() {
        #expect(LoopbackReceiver.requestTarget("GET /favicon.ico HTTP/1.1\r\n\r\n") == "/favicon.ico")
        #expect(LoopbackReceiver.requestTarget("POST /callback HTTP/1.1\r\n\r\n") == nil)
        #expect(LoopbackReceiver.requestTarget("") == nil)
        #expect(LoopbackReceiver.requestTarget("garbage") == nil)
    }

    @Test("query items are decoded")
    func queryItems() {
        let items = LoopbackReceiver.queryItems("/callback?code=AQD-abc_123&state=xyz%3D")
        #expect(items["code"] == "AQD-abc_123")
        #expect(items["state"] == "xyz=")
    }

    @Test("a denial is reported as an error item")
    func denial() {
        let items = LoopbackReceiver.queryItems("/callback?error=access_denied&state=xyz")
        #expect(items["error"] == "access_denied")
        #expect(items["code"] == nil)
    }

    @Test("a callback with no query yields nothing")
    func noQuery() {
        #expect(LoopbackReceiver.queryItems("/callback").isEmpty)
    }

    /// Spotify stopped accepting `localhost` redirect URIs in 2025; the literal loopback
    /// address is required.
    @Test("the redirect URI uses the literal loopback address")
    func redirectURI() {
        #expect(LoopbackReceiver.redirectURI == "http://127.0.0.1:8888/callback")
    }
}

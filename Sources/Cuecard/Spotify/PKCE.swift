import CryptoKit
import Foundation

/// Authorization Code with PKCE. A desktop app cannot keep a client secret, so the
/// secret-less flow is the only correct choice here — nothing confidential ships in the
/// bundle, and the one-time verifier never leaves this process until it is redeemed.
enum PKCE {
    /// Unreserved characters, per RFC 7636 §4.1.
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// RFC 7636 allows 43–128 characters; 64 is comfortably inside that.
    static func verifier(length: Int = 64) -> String {
        precondition((43...128).contains(length), "verifier length is out of spec")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Opaque value echoed back by the authorization server so we can reject a callback
    /// we did not initiate.
    static func state() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        return base64URL(Data(bytes))
    }

    /// base64url without padding — the only encoding the spec accepts.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

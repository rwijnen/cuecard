import Foundation
import Security

/// Stores the Spotify refresh token.
///
/// Keychain first, because a refresh token grants read access to your listening state.
/// A file fallback exists for one specific case: an ad-hoc signed bundle's identity
/// changes on every rebuild, and if the Keychain refuses rather than prompts we would
/// otherwise lose the ability to save at all. The fallback is `0600` in Application
/// Support, which is weaker but not public.
enum SecretStore {
    private static let service = "com.robinwijnen.Cuecard"
    private static let account = "spotify-oauth"

    static func save(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Update in place if it exists; SecItemAdd would return errSecDuplicateItem.
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status != errSecSuccess else { return }

        Log.auth.error("keychain write failed (\(status)); falling back to a 0600 file")
        writeFile(data)
    }

    static func load() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return readFile()
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Fallback file

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cuecard", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("oauth.token")
    }

    private static func writeFile(_ data: Data) {
        let url = fileURL
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func readFile() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

import AppKit
import CryptoKit
import Foundation

/// Downloads and caches album art.
///
/// Two consumers with different needs: the notch card wants an `NSImage`, and
/// `UNNotificationAttachment` wants a file URL — and the notification system *moves* the
/// file it is handed, so every notification gets its own throwaway copy rather than the
/// cached original.
actor ArtworkStore {
    private let session: URLSession
    private let cacheDirectory: URL
    private var memory: [String: NSImage] = [:]

    /// Album art is ~40 KB; a couple of hundred covers is a rounding error on disk and
    /// spares the network on repeat listens.
    private let maximumCachedFiles = 200

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches
            .appendingPathComponent("com.robinwijnen.Cuecard", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// The cached file for this artwork, downloading it if needed. `nil` if there is no
    /// artwork or the download failed — callers fall back to a placeholder.
    func file(for url: URL?) async -> URL? {
        guard let url else { return nil }
        let destination = cacheDirectory.appendingPathComponent(Self.key(for: url))
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  NSImage(data: data) != nil
            else {
                Log.present.error("artwork download rejected: \(url.absoluteString, privacy: .public)")
                return nil
            }
            try data.write(to: destination, options: .atomic)
            prune()
            return destination
        } catch {
            Log.present.error("artwork download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func image(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let key = Self.key(for: url)
        if let cached = memory[key] { return cached }
        guard let file = await file(for: url), let image = NSImage(contentsOf: file) else { return nil }
        memory[key] = image
        // The notch card shows one cover at a time; a handful of recents is plenty.
        if memory.count > 8 { memory.removeAll() }
        return image
    }

    /// A disposable copy for `UNNotificationAttachment`, which takes ownership of
    /// whatever file it is given.
    func attachmentCopy(for url: URL?) async -> URL? {
        guard let source = await file(for: url) else { return nil }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("cuecard-\(UUID().uuidString).jpg")
        do {
            try FileManager.default.copyItem(at: source, to: temporary)
            return temporary
        } catch {
            Log.present.error("could not stage artwork attachment: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Filenames come from the URL digest: stable, collision-free and safe on disk,
    /// which a Spotify CDN path is not.
    static func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private func prune() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maximumCachedFiles else { return }

        let byAge = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for file in byAge.prefix(files.count - maximumCachedFiles) {
            try? manager.removeItem(at: file)
        }
    }
}

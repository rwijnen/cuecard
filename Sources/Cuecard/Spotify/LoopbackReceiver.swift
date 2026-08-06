import Foundation
import Network

/// A single-shot HTTP listener on the loopback interface, used to catch the OAuth
/// redirect.
///
/// A loopback redirect is preferred over a custom `cuecard://` scheme because it works
/// whether or not the bundle happens to be registered with Launch Services — which, for
/// an app built straight out of a source tree, it often is not.
final class LoopbackReceiver {
    /// Fixed, because Spotify matches redirect URIs exactly and the value has to be
    /// typed into the developer dashboard once. Spotify requires the literal
    /// `127.0.0.1`; it stopped accepting `localhost` in 2025.
    static let port: UInt16 = 8888
    static let redirectURI = "http://127.0.0.1:\(port)/callback"

    enum Failure: Error {
        case portUnavailable(String)
        case cancelled
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.robinwijnen.Cuecard.loopback")

    /// Starts listening and returns the query items of the first request to `/callback`.
    /// Stops itself before returning, whatever the outcome.
    func awaitCallback() async throws -> [String: String] {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback only. Nothing off-machine can reach this.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(rawValue: Self.port)!)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Failure.portUnavailable(
                "Port \(Self.port) is already in use. Quit whatever is using it and try again."
            )
        }
        self.listener = listener

        // A continuation must be resumed exactly once; several connections can arrive
        // (favicon requests, browser prefetch), so latch on the first usable one.
        let latch = Latch()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    if case .failed(let error) = state, latch.close() {
                        continuation.resume(throwing: Failure.portUnavailable(error.localizedDescription))
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection) { items in
                        guard latch.close() else { return }
                        self?.stop()
                        continuation.resume(returning: items)
                    }
                }
                listener.start(queue: queue)
                Log.auth.info("listening on \(Self.redirectURI, privacy: .public)")
            }
        } onCancel: {
            if latch.close() { stop() }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Minimal HTTP

    private func handle(_ connection: NWConnection, done: @escaping ([String: String]) -> Void) {
        connection.start(queue: queue)
        // 8 KB is far more than a redirect ever needs; the request line is all we read.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8),
                  let target = Self.requestTarget(request),
                  target.hasPrefix("/callback")
            else {
                Self.reply(on: connection, status: "404 Not Found", body: "Not here.")
                return
            }
            Self.reply(on: connection, status: "200 OK", body: Self.successPage)
            done(Self.queryItems(target))
        }
    }

    /// Pulls the path+query out of `GET /callback?code=… HTTP/1.1`.
    static func requestTarget(_ request: String) -> String? {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    static func queryItems(_ target: String) -> [String: String] {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)") else { return [:] }
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            if let value = item.value { result[item.name] = value }
        }
    }

    private static func reply(on connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successPage = """
    <!doctype html><meta charset="utf-8"><title>Cuecard</title>
    <style>
      body{font:15px -apple-system,system-ui,sans-serif;display:grid;place-items:center;
           height:100vh;margin:0;background:#111;color:#eee}
      div{text-align:center}h1{font-size:20px;font-weight:600;margin:0 0 .4em}
      p{color:#999;margin:0}
    </style>
    <div><h1>Cuecard is connected</h1><p>You can close this tab.</p></div>
    """
}

/// One-shot gate. `close()` returns true for the first caller only.
private final class Latch {
    private var open = true
    private let lock = NSLock()

    func close() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard open else { return false }
        open = false
        return true
    }
}

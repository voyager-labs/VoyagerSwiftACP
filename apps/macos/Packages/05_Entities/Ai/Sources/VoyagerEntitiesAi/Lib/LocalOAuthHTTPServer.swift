import Foundation
import Network

/// The result of a successful OAuth callback.
struct OAuthCallbackResult: Sendable {
    let code: String
    let state: String
}

/// Errors that can occur during the local OAuth callback.
enum OAuthCallbackError: Error, Sendable, Equatable {
    case cancelled
    case invalidCallback(String)
    case accessDenied(String)
    case serverStartFailed(String)
}

/// A lightweight HTTP server that listens on `localhost:{port}` for a single
/// OAuth authorization callback, then stops.
///
/// Uses `NWListener` from the Network framework — no external dependencies.
///
/// **Thread safety:** The continuation is set before the listener accepts
/// connections (the browser cannot navigate faster than the code that follows
/// `start()`), and it is consumed exactly once in the connection handler.
/// Deinit cancels the listener, preventing dangling handlers.
final class LocalOAuthHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private let expectedPath: String
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<OAuthCallbackResult, Error>?
    private var isCancelled = false

    init(port: UInt16, expectedPath: String = "/auth/callback") {
        self.port = port
        self.expectedPath = expectedPath
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OAuthCallbackError.serverStartFailed("Invalid port: \(port)")
        }
        guard !isFlowCancelled() else { throw OAuthCallbackError.cancelled }

        let listener = try NWListener(using: .tcp, on: nwPort)

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        lock.lock()
        if isCancelled {
            lock.unlock()
            listener.cancel()
            throw OAuthCallbackError.cancelled
        }
        self.listener = listener
        lock.unlock()

        listener.start(queue: .global(qos: .userInitiated))
    }

    /// Wait for the OAuth callback to arrive. Resolves with the auth code
    /// or throws on error / cancellation.
    func waitForCallback() async throws -> OAuthCallbackResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: OAuthCallbackError.cancelled)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: {
            self.cancel()
        }
    }

    /// Convenience: start, wait with a timeout, then stop.
    func startAndWait(timeout: TimeInterval = 300) async throws -> OAuthCallbackResult {
        try start()

        return try await withTaskCancellationHandler {
            defer { stop() }

            return try await withThrowingTaskGroup(of: OAuthCallbackResult.self) { group in
                group.addTask {
                    try await self.waitForCallback()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    let error = OAuthCallbackError.serverStartFailed("Timeout waiting for OAuth callback")
                    self.cancel(with: error)
                    throw error
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } onCancel: {
            self.cancel()
        }
    }

    func stop() {
        lock.lock()
        let currentListener = listener
        listener = nil
        lock.unlock()

        currentListener?.cancel()
    }

    func cancel() {
        cancel(with: OAuthCallbackError.cancelled)
    }

    private func cancel(with error: Error) {
        lock.lock()
        let currentListener = listener
        let currentContinuation = continuation
        listener = nil
        continuation = nil
        isCancelled = true
        lock.unlock()

        currentListener?.cancel()
        currentContinuation?.resume(throwing: error)
    }

    private func isFlowCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            processRequest(request, on: connection)
        }
    }

    private func processRequest(_ request: String, on connection: NWConnection) {
        // Parse "GET /path?query HTTP/1.1"
        let tokens = request.components(separatedBy: " ")
        guard tokens.count >= 2, tokens[0] == "GET" else {
            connection.cancel()
            return
        }
        let path = tokens[1]

        if path.hasPrefix(expectedPath) {
            handleCallback(path: path, on: connection)
        } else if path.hasPrefix("/cancel") {
            respond(html: Self.htmlPage(title: "Cancelled", body: "Authentication was cancelled."), on: connection)
            resolve(.failure(OAuthCallbackError.cancelled))
        } else {
            connection.cancel()
        }
    }

    private func handleCallback(path: String, on connection: NWConnection) {
        guard let queryIndex = path.firstIndex(of: "?") else {
            respond(
                html: Self.htmlPage(title: "Error", body: "Invalid callback URL."),
                on: connection
            )
            resolve(.failure(OAuthCallbackError.invalidCallback("No query string")))
            return
        }

        let query = String(path[path.index(after: queryIndex)...])
        let params = Self.parseQuery(query)

        if let error = params["error"] {
            let desc = params["error_description"] ?? error
            respond(
                html: Self.htmlPage(title: "Authentication Failed", body: desc),
                on: connection
            )
            resolve(.failure(OAuthCallbackError.accessDenied(desc)))
            return
        }

        guard let code = params["code"], let state = params["state"] else {
            respond(
                html: Self.htmlPage(title: "Error", body: "Missing authorization parameters."),
                on: connection
            )
            resolve(.failure(OAuthCallbackError.invalidCallback("Missing code or state")))
            return
        }

        respond(
            html: Self.htmlPage(title: "Success!", body: "You can close this tab and return to Voyager."),
            on: connection
        )
        resolve(.success(OAuthCallbackResult(code: code, state: state)))
    }

    // MARK: - HTTP Response

    private func respond(html: String, on connection: NWConnection) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        Content-Length: \(html.utf8.count)\r
        \r
        """
        let response = header + html
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resolve(_ result: Result<OAuthCallbackResult, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()

        guard let cont else { return }
        switch result {
        case let .success(value): cont.resume(returning: value)
        case let .failure(error): cont.resume(throwing: error)
        }
    }

    // MARK: - Static Helpers (testable)

    static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let parts = pair.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[0]
            let value = parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[1]
            result[key] = value
        }
        return result
    }

    static func htmlPage(title: String, body: String) -> String {
        """
        <!DOCTYPE html><html><head><title>\(title)</title></head>\
        <body style="font-family:-apple-system,sans-serif;display:flex;\
        justify-content:center;align-items:center;height:100vh;margin:0;\
        background:#f5f5f7;">\
        <div style="text-align:center;padding:40px;background:white;\
        border-radius:12px;box-shadow:0 2px 10px rgba(0,0,0,0.1);">\
        <h1 style="color:#1d1d1f;">\(title)</h1>\
        <p style="color:#6e6e73;">\(body)</p>\
        </div></body></html>
        """
    }
}

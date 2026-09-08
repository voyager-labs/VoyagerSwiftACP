import Foundation

final class RegistryURLProtocol: URLProtocol {
    private static let box = HandlerBox()

    private final class HandlerBox: @unchecked Sendable {
        /// Invariant: the lock guards the single handler slot.
        let lock = NSLock()
        var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    }

    /// Test-local response handler. The lock protects the single mutable slot.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            box.lock.lock()
            defer { box.lock.unlock() }
            return box.handler
        }
        set {
            box.lock.lock()
            box.handler = newValue
            box.lock.unlock()
        }
    }

    static func reset() {
        handler = nil
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, request.url != nil else {
            // No handler installed: fail loudly so accidental network use in the
            // offline suite surfaces as a test failure.
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

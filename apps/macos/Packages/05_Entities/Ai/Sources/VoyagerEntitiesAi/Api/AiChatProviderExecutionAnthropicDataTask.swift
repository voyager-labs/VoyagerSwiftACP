import Foundation

struct AnthropicStreamingDataTaskEvent {
    enum Kind {
        case response(HTTPURLResponse)
        case data(Data)
    }

    let kind: Kind
}

final class AnthropicStreamingDataTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<AnthropicStreamingDataTaskEvent, Error>.Continuation?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false

    init(request: URLRequest, configuration: URLSessionConfiguration) {
        self.request = request
        self.configuration = configuration
        super.init()
    }

    func events() -> AsyncThrowingStream<AnthropicStreamingDataTaskEvent, Error> {
        AsyncThrowingStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
            }
            continuation.onTermination = { @Sendable _ in
                self.cancel()
            }
            self.start()
        }
    }

    func cancel() {
        let currentTask: URLSessionDataTask?
        let currentSession: URLSession?
        lock.lock()
        cancelled = true
        currentTask = task
        currentSession = session
        lock.unlock()
        currentTask?.cancel()
        currentSession?.invalidateAndCancel()
    }

    private func start() {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        let shouldCancel: Bool
        lock.lock()
        self.session = session
        self.task = task
        shouldCancel = cancelled
        lock.unlock()

        if shouldCancel {
            task.cancel()
            session.invalidateAndCancel()
            return
        }
        task.resume()
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void,
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            yield(.init(kind: .response(httpResponse)))
            completionHandler(.allow)
        } else {
            finish(throwing: AiHTTPError.networkError("Non-HTTP response"))
            completionHandler(.cancel)
        }
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        yield(.init(kind: .data(data)))
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(throwing: error)
        } else {
            finish(throwing: nil)
        }
        session.finishTasksAndInvalidate()
        lock.withLock {
            self.session = nil
            self.task = nil
        }
    }

    private func yield(_ event: AnthropicStreamingDataTaskEvent) {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(event)
    }

    private func finish(throwing error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}

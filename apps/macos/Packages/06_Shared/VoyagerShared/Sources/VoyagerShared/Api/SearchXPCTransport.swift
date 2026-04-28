import Foundation
import Logging

public enum SearchXPCTransport {
    private nonisolated static let logger = Logger(label: "Voyager.FilterSearchXPC")
    private nonisolated static let filterTimeoutSeconds: TimeInterval = 20
    private nonisolated static let queryTimeoutSeconds: TimeInterval = 25
    private nonisolated static let recentTimeoutSeconds: TimeInterval = 20
    private nonisolated static let tagTimeoutSeconds: TimeInterval = 20

    public nonisolated static func applyFilters(
        _ request: FiltersOnlyRequestPayload,
    ) async throws -> SearchResponsePayload {
        let requestId = UUID().uuidString
        logger.info("Dispatching filter search XPC request: id=\(requestId)")
        let requestData = try encodeRequestData(from: request)

        return try await withCheckedThrowingContinuation(isolation: nil) { @Sendable continuation in
            let context = RequestContext(
                requestId: requestId,
                logger: logger,
                continuation: continuation,
                decodeResponse: decodeSearchResponse,
            )
            context.start(requestData: requestData, timeout: filterTimeoutSeconds)
        }
    }

    public nonisolated static func querySearch(
        _ request: SearchRequestPayload,
    ) async throws -> SearchResponsePayload {
        let requestId = UUID().uuidString
        logger.info("Dispatching query search XPC request: id=\(requestId)")
        let requestData = try encodeRequestData(from: request)

        return try await withCheckedThrowingContinuation(isolation: nil) { @Sendable continuation in
            let context = RequestContext(
                requestId: requestId,
                logger: logger,
                continuation: continuation,
                decodeResponse: decodeSearchResponse,
            )
            context.startQuery(requestData: requestData, timeout: queryTimeoutSeconds)
        }
    }

    public nonisolated static func recentSearch(
        _ request: RecentSearchRequestPayload,
    ) async throws -> RecentSearchResponsePayload {
        let requestId = UUID().uuidString
        logger.info("Dispatching recent search XPC request: id=\(requestId)")
        let requestData = try encodeRequestData(from: request)

        return try await withCheckedThrowingContinuation(isolation: nil) { @Sendable continuation in
            let context = RequestContext(
                requestId: requestId,
                logger: logger,
                continuation: continuation,
                decodeResponse: { data in
                    try decodeResponse(RecentSearchResponsePayload.self, from: data)
                },
            )
            context.startRecent(requestData: requestData, timeout: recentTimeoutSeconds)
        }
    }

    public nonisolated static func tagSearch(
        _ request: TagSearchRequestPayload,
    ) async throws -> TagSearchResponsePayload {
        let requestId = UUID().uuidString
        logger.info("Dispatching tag search XPC request: id=\(requestId)")
        let requestData = try encodeRequestData(from: request)

        return try await withCheckedThrowingContinuation(isolation: nil) { @Sendable continuation in
            let context = RequestContext(
                requestId: requestId,
                logger: logger,
                continuation: continuation,
                decodeResponse: { data in
                    try decodeResponse(TagSearchResponsePayload.self, from: data)
                },
            )
            context.startTag(requestData: requestData, timeout: tagTimeoutSeconds)
        }
    }
}

private extension SearchXPCTransport {
    nonisolated static func encodeRequestData(from request: SearchRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    nonisolated static func encodeRequestData(from request: FiltersOnlyRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    nonisolated static func encodeRequestData(from request: RecentSearchRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    nonisolated static func encodeRequestData(from request: TagSearchRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    nonisolated static func decodeResponse<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data,
    ) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HelperSearchError(code: "DECODE_FAILED", message: error.localizedDescription)
        }
    }

    nonisolated static func decodeSearchResponse(from data: Data) throws -> SearchResponsePayload {
        let response = try decodeResponse(SearchResponsePayload.self, from: data)
        if let payloadError = response.error {
            throw HelperSearchError(code: payloadError.code, message: payloadError.details)
        }
        return response
    }

    enum OperationKind {
        case filter
        case query
        case recent
        case tag

        nonisolated var label: String {
            switch self {
            case .filter:
                "Filter search"
            case .query:
                "Query search"
            case .recent:
                "Recent search"
            case .tag:
                "Tag search"
            }
        }
    }

    final class RequestContext<Response: Sendable>: @unchecked Sendable {
        private let requestId: String
        private let logger: Logger
        private let queue: DispatchQueue
        private let decodeResponse: @Sendable (Data) throws -> Response
        private let lock = NSLock()

        private nonisolated(unsafe) var continuation: CheckedContinuation<Response, Error>?
        private nonisolated(unsafe) var connection: NSXPCConnection?
        private nonisolated(unsafe) var timeoutWorkItem: DispatchWorkItem?

        nonisolated init(
            requestId: String,
            logger: Logger,
            continuation: CheckedContinuation<Response, Error>,
            decodeResponse: @escaping @Sendable (Data) throws -> Response,
        ) {
            self.requestId = requestId
            self.logger = logger
            self.continuation = continuation
            self.decodeResponse = decodeResponse
            queue = DispatchQueue(label: "fm.voyager.search.filter.xpc.\(requestId)")
        }

        nonisolated func start(requestData: Data, timeout: TimeInterval) {
            startOperation(kind: .filter, requestData: requestData, timeout: timeout)
        }

        nonisolated func startQuery(requestData: Data, timeout: TimeInterval) {
            startOperation(kind: .query, requestData: requestData, timeout: timeout)
        }

        nonisolated func startRecent(requestData: Data, timeout: TimeInterval) {
            startOperation(kind: .recent, requestData: requestData, timeout: timeout)
        }

        nonisolated func startTag(requestData: Data, timeout: TimeInterval) {
            startOperation(kind: .tag, requestData: requestData, timeout: timeout)
        }

        private nonisolated func startOperation(
            kind: OperationKind,
            requestData: Data,
            timeout: TimeInterval,
        ) {
            queue.async {
                let operationLabel = kind.label
                let connection = self.makeConnection(operationLabel: operationLabel)
                self.scheduleTimeout(timeout: timeout, operationLabel: operationLabel)

                guard let proxy = self.makeProxy(connection: connection, operationLabel: operationLabel) else {
                    return
                }

                switch kind {
                case .filter:
                    proxy.applyFilters(requestData) { [self] responseData, error in
                        queue.async {
                            self.handleReply(responseData: responseData, error: error, operationLabel: operationLabel)
                        }
                    }
                case .query:
                    proxy.querySearch(requestData) { [self] responseData, error in
                        queue.async {
                            self.handleReply(responseData: responseData, error: error, operationLabel: operationLabel)
                        }
                    }
                case .recent:
                    proxy.recentSearch(requestData) { [self] responseData, error in
                        queue.async {
                            self.handleReply(responseData: responseData, error: error, operationLabel: operationLabel)
                        }
                    }
                case .tag:
                    proxy.tagSearch(requestData) { [self] responseData, error in
                        queue.async {
                            self.handleReply(responseData: responseData, error: error, operationLabel: operationLabel)
                        }
                    }
                }
            }
        }

        private nonisolated func makeConnection(operationLabel: String) -> NSXPCConnection {
            let connection = NSXPCConnection(serviceName: FilterSearchXPCServiceConstants.machServiceName)
            storeConnection(connection)
            connection.remoteObjectInterface = NSXPCInterface(with: FilterSearchXPCServiceProtocol.self)
            connection.interruptionHandler = { [self] in
                logger.warning("\(operationLabel) XPC interrupted: id=\(requestId)")
                finish(.failure(HelperSearchError(code: "HELPER_INTERRUPTED", message: nil)))
            }
            connection.invalidationHandler = { [self] in
                logger.info("\(operationLabel) XPC invalidated: id=\(requestId)")
            }
            connection.resume()
            return connection
        }

        private nonisolated func scheduleTimeout(timeout: TimeInterval, operationLabel: String) {
            let timeoutWorkItem = DispatchWorkItem { [self] in
                logger.warning("\(operationLabel) helper timeout: id=\(requestId)")
                finish(.failure(HelperSearchError(code: "HELPER_TIMEOUT", message: nil)))
            }
            storeTimeoutWorkItem(timeoutWorkItem)
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
        }

        private nonisolated func makeProxy(
            connection: NSXPCConnection,
            operationLabel: String,
        ) -> FilterSearchXPCServiceProtocol? {
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [self] error in
                logger.warning("\(operationLabel) XPC transport failed: id=\(requestId) error=\(error)")
                finish(.failure(error))
            }) as? FilterSearchXPCServiceProtocol else {
                finish(.failure(HelperSearchError(code: "PROXY_UNAVAILABLE", message: nil)))
                return nil
            }

            return proxy
        }

        private nonisolated func handleReply(
            responseData: Data?,
            error: NSError?,
            operationLabel: String,
        ) {
            if let error {
                logger.warning("\(operationLabel) XPC failed: id=\(requestId) error=\(error)")
                finish(.failure(error))
                return
            }

            guard let responseData else {
                finish(.failure(HelperSearchError(code: "EMPTY_RESPONSE", message: nil)))
                return
            }

            do {
                let response = try decodeResponse(responseData)
                logger.info("\(operationLabel) response received: id=\(requestId)")
                finish(.success(response))
            } catch {
                finish(.failure(error))
            }
        }

        private nonisolated func finish(_ result: Result<Response, Error>) {
            lock.lock()
            let currentContinuation = continuation
            let currentConnection = connection
            let currentTimeoutWorkItem = timeoutWorkItem
            continuation = nil
            connection = nil
            timeoutWorkItem = nil
            lock.unlock()

            guard let currentContinuation else { return }
            currentTimeoutWorkItem?.cancel()
            currentConnection?.invalidate()

            switch result {
            case let .success(response):
                currentContinuation.resume(returning: response)
            case let .failure(error):
                currentContinuation.resume(throwing: error)
            }
        }

        private nonisolated func storeConnection(_ connection: NSXPCConnection) {
            lock.lock()
            self.connection = connection
            lock.unlock()
        }

        private nonisolated func storeTimeoutWorkItem(_ timeoutWorkItem: DispatchWorkItem) {
            lock.lock()
            self.timeoutWorkItem = timeoutWorkItem
            lock.unlock()
        }
    }
}

private struct HelperSearchError: LocalizedError {
    let code: String
    let message: String?

    var errorDescription: String? {
        if let message {
            return "\(code): \(message)"
        }
        return code
    }
}

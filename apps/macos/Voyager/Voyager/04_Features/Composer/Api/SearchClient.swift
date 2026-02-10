import ComposableArchitecture
import Foundation
import Logging

struct SearchClient: Sendable {
    var search: @Sendable (_ request: SearchRequestPayload) async throws -> SearchResponsePayload
    var applyFilters: @Sendable (_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload
}

extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = {
        SearchClient(
            search: { request in
                try await searchViaHelper(request)
            },
            applyFilters: { request in
                try await applyFiltersViaHelper(request)
            },
        )
    }()

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil, error: nil) },
    )
}

extension SearchClient: TestDependencyKey {}

private extension SearchClient {
    static func searchViaHelper(_ request: SearchRequestPayload) async throws -> SearchResponsePayload {
        try await FilterSearchXPCClient.querySearch(request)
    }

    static func applyFiltersViaHelper(_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload {
        try await FilterSearchXPCClient.applyFilters(request)
    }
}

private enum FilterSearchXPCClient {
    private nonisolated static let logger = Logger(label: "Voyager.FilterSearchXPC")
    private nonisolated static let filterTimeoutSeconds: TimeInterval = 8
    private nonisolated static let queryTimeoutSeconds: TimeInterval = 25

    static func applyFilters(
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
            )
            context.start(requestData: requestData, timeout: filterTimeoutSeconds)
        }
    }

    static func querySearch(
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
            )
            context.startQuery(requestData: requestData, timeout: queryTimeoutSeconds)
        }
    }
}

private extension FilterSearchXPCClient {
    static func encodeRequestData(from request: SearchRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    static func encodeRequestData(from request: FiltersOnlyRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    enum OperationKind {
        case filter
        case query

        nonisolated var label: String {
            switch self {
            case .filter:
                "Filter search"
            case .query:
                "Query search"
            }
        }
    }

    final class RequestContext: @unchecked Sendable {
        private let requestId: String
        private let logger: Logger
        private let queue: DispatchQueue
        private let lock = NSLock()

        private nonisolated(unsafe) var continuation: CheckedContinuation<SearchResponsePayload, Error>?
        private nonisolated(unsafe) var connection: NSXPCConnection?
        private nonisolated(unsafe) var timeoutWorkItem: DispatchWorkItem?

        nonisolated init(
            requestId: String,
            logger: Logger,
            continuation: CheckedContinuation<SearchResponsePayload, Error>,
        ) {
            self.requestId = requestId
            self.logger = logger
            self.continuation = continuation
            queue = DispatchQueue(label: "fm.voyager.search.filter.xpc.\(requestId)")
        }

        nonisolated func start(requestData: Data, timeout: TimeInterval) {
            startOperation(
                kind: .filter,
                requestData: requestData,
                timeout: timeout,
            )
        }

        nonisolated func startQuery(requestData: Data, timeout: TimeInterval) {
            startOperation(
                kind: .query,
                requestData: requestData,
                timeout: timeout,
            )
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
                    Task { @MainActor in
                        proxy.applyFilters(requestData) { [self] responseData, error in
                            queue.async {
                                self.handleReply(
                                    responseData: responseData,
                                    error: error,
                                    operationLabel: operationLabel,
                                )
                            }
                        }
                    }
                case .query:
                    Task { @MainActor in
                        proxy.querySearch(requestData) { [self] responseData, error in
                            queue.async {
                                self.handleReply(
                                    responseData: responseData,
                                    error: error,
                                    operationLabel: operationLabel,
                                )
                            }
                        }
                    }
                }
            }
        }

        private nonisolated func makeConnection(
            operationLabel: String,
        ) -> NSXPCConnection {
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
                logger.warning(
                    "\(operationLabel) XPC transport failed: id=\(requestId) error=\(error)",
                )
                finish(.failure(error))
            }) as? FilterSearchXPCServiceProtocol
            else {
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
                logger.warning(
                    "\(operationLabel) XPC failed: id=\(requestId) error=\(error)",
                )
                finish(.failure(error))
                return
            }

            guard let responseData else {
                finish(.failure(HelperSearchError(code: "EMPTY_RESPONSE", message: nil)))
                return
            }

            Task { @MainActor [self, responseData] in
                do {
                    let response = try JSONDecoder().decode(SearchResponsePayload.self, from: responseData)

                    if let payloadError = response.error {
                        logger.warning(
                            "\(operationLabel) payload error: id=\(requestId) code=\(payloadError.code)",
                        )
                        finish(
                            .failure(
                                HelperSearchError(
                                    code: payloadError.code,
                                    message: payloadError.details,
                                ),
                            ),
                        )
                        return
                    }

                    logger.info(
                        "\(operationLabel) response received: id=\(requestId) items=\(response.itemCount)",
                    )
                    finish(.success(response))
                } catch {
                    finish(
                        .failure(
                            HelperSearchError(code: "DECODE_FAILED", message: error.localizedDescription),
                        ),
                    )
                }
            }
        }

        private nonisolated func finish(_ result: Result<SearchResponsePayload, Error>) {
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
            currentContinuation.resume(with: result)
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

extension DependencyValues {
    nonisolated var searchClient: SearchClient {
        get { self[SearchClient.self] }
        set { self[SearchClient.self] = newValue }
    }
}

import ComposableArchitecture
import Foundation
import Logging
import SwiftDotenv

struct SearchRequestPayload: Codable, Equatable, Sendable {
    let query: String
    let filters: SearchFiltersPayload
}

struct SearchClient: Sendable {
    var search: @Sendable (_ request: SearchRequestPayload) async throws -> SearchResponsePayload
    var applyFilters: @Sendable (_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload
}

extension SearchClient: DependencyKey {
    static let liveValue: SearchClient = {
        @Sendable
        func post<U: Decodable>(path: String, body: some Encodable) async throws -> U {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            let baseURL = await MainActor.run { Dotenv.publicBackendURL }
            let appVersion = await MainActor.run { AppVersionInfo.shortVersion }
            let deviceId = await MainActor.run { DeviceIdentifierProvider.current() }
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let url = baseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let deviceId {
                request.setValue(deviceId, forHTTPHeaderField: "X-Voyager-Device-Id")
            }
            request.setValue(appVersion, forHTTPHeaderField: "X-Voyager-App-Version")
            request.setValue(osVersion, forHTTPHeaderField: "X-Voyager-OS-Version")
            request.httpBody = try encoder.encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200 ..< 300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            return try decoder.decode(U.self, from: data)
        }

        return SearchClient(
            search: { request in
                try await post(path: "api/collection", body: request)
            },
            applyFilters: { request in
                try await applyFiltersViaHelper(request)
            },
        )
    }()

    nonisolated(unsafe) static var testValue: SearchClient = .init(
        search: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
        applyFilters: { _ in .init(itemCount: 0, appliedFilters: nil, items: nil) },
    )
}

extension SearchClient: TestDependencyKey {}

private extension SearchClient {
    static func applyFiltersViaHelper(_ request: FiltersOnlyRequestPayload) async throws -> SearchResponsePayload {
        try await FilterSearchXPCClient.applyFilters(request)
    }
}

private enum FilterSearchXPCClient {
    private nonisolated(unsafe) static let logger = Logger(label: "Voyager.FilterSearchXPC")
    private nonisolated(unsafe) static let timeoutSeconds: TimeInterval = 8

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
            context.start(requestData: requestData, timeout: timeoutSeconds)
        }
    }
}

private extension FilterSearchXPCClient {
    static func encodeRequestData(from request: FiltersOnlyRequestPayload) throws -> Data {
        do {
            return try JSONEncoder().encode(request)
        } catch {
            throw HelperSearchError(code: "ENCODE_FAILED", message: error.localizedDescription)
        }
    }

    final class RequestContext: @unchecked Sendable {
        private nonisolated(unsafe) let requestId: String
        private nonisolated(unsafe) let logger: Logger
        private nonisolated(unsafe) let queue: DispatchQueue
        private nonisolated(unsafe) let lock = NSLock()

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
            queue.async {
                let connection = NSXPCConnection(serviceName: FilterSearchXPCServiceConstants.machServiceName)
                self.storeConnection(connection)
                connection.remoteObjectInterface = NSXPCInterface(with: FilterSearchXPCServiceProtocol.self)
                connection.interruptionHandler = { [self] in
                    logger.warning("Filter search XPC interrupted: id=\(requestId)")
                    finish(.failure(HelperSearchError(code: "HELPER_INTERRUPTED", message: nil)))
                }
                connection.invalidationHandler = { [self] in
                    logger.info("Filter search XPC invalidated: id=\(requestId)")
                }
                connection.resume()

                let timeoutWorkItem = DispatchWorkItem { [self] in
                    logger.warning("Filter search helper timeout: id=\(requestId)")
                    finish(.failure(HelperSearchError(code: "HELPER_TIMEOUT", message: nil)))
                }
                self.storeTimeoutWorkItem(timeoutWorkItem)
                self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [self] error in
                    self.logger.warning(
                        "Filter search XPC transport failed: id=\(self.requestId) error=\(error)",
                    )
                    self.finish(.failure(error))
                }) as? FilterSearchXPCServiceProtocol
                else {
                    self.finish(.failure(HelperSearchError(code: "PROXY_UNAVAILABLE", message: nil)))
                    return
                }

                proxy.applyFilters(requestData) { [self] responseData, error in
                    queue.async {
                        self.handleReply(responseData: responseData, error: error)
                    }
                }
            }
        }

        private nonisolated func handleReply(responseData: Data?, error: NSError?) {
            if let error {
                logger.warning(
                    "Filter search XPC failed: id=\(requestId) error=\(error)",
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
                    logger.info(
                        "Filter search response received: id=\(requestId) items=\(response.itemCount)",
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

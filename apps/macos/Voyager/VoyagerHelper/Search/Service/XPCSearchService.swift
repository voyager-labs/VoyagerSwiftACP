import Foundation
import Logging

final class XPCSearchService: NSObject, FilterSearchXPCServiceProtocol {
    private let service: SpotlightSearchService
    private let logger: Logger

    nonisolated init(service: SpotlightSearchService, logger: Logger) {
        self.service = service
        self.logger = logger
    }

    nonisolated func applyFilters(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void,
    ) {
        let replyBox = ReplyBox(reply)
        let service = service
        let logger = logger
        Task { @MainActor in
            do {
                let request = try Self.decodeRequest(from: requestData)
                let queryService = SearchQueryService(searchService: service)
                let response = try await Task.detached(priority: .userInitiated) {
                    try await queryService.executeQuery(request.filters)
                }
                .value
                let responseData = try Self.encodeResponse(response)
                replyBox.call(responseData, nil)
            } catch {
                logger.error("Filter search XPC failed: \(error)")
                replyBox.call(nil, Self.makeNSError(from: error))
            }
        }
    }

    nonisolated func querySearch(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void,
    ) {
        let replyBox = ReplyBox(reply)
        let service = service
        let logger = logger
        Task { @MainActor in
            do {
                let request = try Self.decodeQueryRequest(from: requestData)
                let queryService = SearchQueryService(searchService: service)
                let response = await Task.detached(priority: .userInitiated) {
                    await queryService.querySearch(request)
                }
                .value
                let responseData = try Self.encodeResponse(response)
                replyBox.call(responseData, nil)
            } catch {
                logger.error("Query search XPC failed: \(error)")
                replyBox.call(nil, Self.makeNSError(from: error))
            }
        }
    }

    private static func decodeRequest(from data: Data) throws -> FiltersOnlyRequestPayload {
        try decodePayload(FiltersOnlyRequestPayload.self, from: data)
    }

    private static func encodeResponse(_ response: SearchResponsePayload) throws -> Data {
        do {
            return try JSONEncoder().encode(response)
        } catch {
            throw ServiceError.responseEncodingFailed(details: error.localizedDescription)
        }
    }

    private static func decodeQueryRequest(from data: Data) throws -> SearchRequestPayload {
        try decodePayload(SearchRequestPayload.self, from: data)
    }

    private static func decodePayload<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ServiceError.invalidRequest(details: error.localizedDescription)
        }
    }

    private static func makeNSError(from error: Error) -> NSError {
        if let serviceError = error as? ServiceError {
            return serviceError.asNSError
        }
        return ServiceError.executionFailed(details: String(describing: error)).asNSError
    }

    private enum ServiceError: Error {
        case invalidRequest(details: String)
        case responseEncodingFailed(details: String)
        case executionFailed(details: String)

        var asNSError: NSError {
            let code: Int
            let label: String
            let details: String

            switch self {
            case let .invalidRequest(value):
                code = 1001
                label = "INVALID_REQUEST"
                details = value
            case let .responseEncodingFailed(value):
                code = 1002
                label = "RESPONSE_ENCODING_FAILED"
                details = value
            case let .executionFailed(value):
                code = 1003
                label = "EXECUTION_FAILED"
                details = value
            }

            return NSError(
                domain: "Voyager.FilterSearchXPC",
                code: code,
                userInfo: [
                    NSLocalizedDescriptionKey: label,
                    "details": details,
                ],
            )
        }
    }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var reply: ((Data?, NSError?) -> Void)?

    nonisolated init(_ reply: @escaping (Data?, NSError?) -> Void) {
        self.reply = reply
    }

    nonisolated func call(_ data: Data?, _ error: NSError?) {
        lock.lock()
        let captured = reply
        reply = nil
        lock.unlock()
        captured?(data, error)
    }
}

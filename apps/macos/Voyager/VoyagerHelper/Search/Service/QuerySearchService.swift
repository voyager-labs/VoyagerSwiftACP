import Foundation
import Logging
import SwiftDotenv

struct QuerySearchService: Sendable {
    private nonisolated(unsafe) static let backendRequestTimeout: TimeInterval = 20

    private let filterService: FilterSearchService
    private let logger: Logger

    init(
        filterService: FilterSearchService,
        logger: Logger = Logger(label: "VoyagerHelper.QuerySearchService"),
    ) {
        self.filterService = filterService
        self.logger = logger
    }

    func querySearch(
        _ request: SearchRequestPayload,
        backendURLOverride: String? = nil,
    ) async throws -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return try await filterService.applyFilters(request.filters)
        }

        return try await requestBackendQuerySearch(request, backendURLOverride: backendURLOverride)
    }

    private func requestBackendQuerySearch(
        _ request: SearchRequestPayload,
        backendURLOverride: String?,
    ) async throws -> SearchResponsePayload {
        let baseURL = try await resolveBackendBaseURL(override: backendURLOverride)
        let url = baseURL.appendingPathComponent("api/collection")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = Self.backendRequestTimeout

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode
        else {
            logger.warning("Backend query search returned non-2xx response")
            throw QuerySearchError.backendResponseInvalid
        }

        do {
            return try JSONDecoder().decode(SearchResponsePayload.self, from: data)
        } catch {
            throw QuerySearchError.backendDecodeFailed(error.localizedDescription)
        }
    }

    private func resolveBackendBaseURL(override: String?) async throws -> URL {
        if let override,
           override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let overrideURL = URL(string: trimmedOverride) else {
                logger.error("Backend query search unavailable: invalid override backend URL")
                throw QuerySearchError.backendURLInvalid(trimmedOverride)
            }
            return overrideURL
        }

        let rawValue = await MainActor.run {
            Dotenv["PUBLIC_BACKEND_URL"]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let rawValue else {
            logger.error("Backend query search unavailable: missing PUBLIC_BACKEND_URL")
            throw QuerySearchError.backendURLMissing
        }
        guard rawValue.isEmpty == false else {
            logger.error("Backend query search unavailable: empty PUBLIC_BACKEND_URL")
            throw QuerySearchError.backendURLMissing
        }
        guard let baseURL = URL(string: rawValue) else {
            logger.error("Backend query search unavailable: invalid PUBLIC_BACKEND_URL")
            throw QuerySearchError.backendURLInvalid(rawValue)
        }
        return baseURL
    }
}

private enum QuerySearchError: LocalizedError {
    case backendURLMissing
    case backendURLInvalid(String)
    case backendResponseInvalid
    case backendDecodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .backendURLMissing:
            "BACKEND_URL_MISSING"
        case let .backendURLInvalid(rawValue):
            "BACKEND_URL_INVALID: \(rawValue)"
        case .backendResponseInvalid:
            "BACKEND_RESPONSE_INVALID"
        case let .backendDecodeFailed(details):
            "BACKEND_DECODE_FAILED: \(details)"
        }
    }
}

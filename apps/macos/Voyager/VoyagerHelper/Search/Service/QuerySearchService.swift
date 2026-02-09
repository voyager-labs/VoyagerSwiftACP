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

        let plannedResponse: SearchResponsePayload
        do {
            plannedResponse = try await requestBackendQuerySearch(
                request,
                backendURLOverride: backendURLOverride,
            )
        } catch {
            logger.warning("Backend query planning failed: \(error)")
            return makeErrorResponse(
                from: error,
                fallbackFilters: request.filters,
            )
        }

        if plannedResponse.error != nil {
            return plannedResponse
        }

        let plannedFilters: SearchFiltersPayload
        do {
            plannedFilters = try makePlannedFilters(from: plannedResponse.appliedFilters)
        } catch {
            logger.warning("Backend query planning output invalid: \(error)")
            return makeErrorResponse(
                from: error,
                fallbackFilters: request.filters,
            )
        }

        return try await filterService.applyFilters(plannedFilters)
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

    private func makePlannedFilters(from appliedFilters: AppliedFiltersPayload?) throws -> SearchFiltersPayload {
        guard let appliedFilters else {
            logger.error("Backend query search response missing appliedFilters")
            throw QuerySearchError.appliedFiltersMissing
        }

        return SearchFiltersPayload(
            scopes: appliedFilters.scopes ?? [],
            conditions: appliedFilters.conditions ?? [],
        )
    }

    private func makeErrorResponse(
        from error: Error,
        fallbackFilters: SearchFiltersPayload,
    ) -> SearchResponsePayload {
        let payloadError = mapErrorPayload(from: error)
        return SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: fallbackFilters.scopes,
                conditions: fallbackFilters.conditions,
            ),
            items: [],
            error: payloadError,
        )
    }

    private func mapErrorPayload(from error: Error) -> SearchErrorPayload {
        if let queryError = error as? QuerySearchError {
            return SearchErrorPayload(
                code: queryError.payloadCode,
                details: queryError.payloadDetails,
            )
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return SearchErrorPayload(code: "BACKEND_TIMEOUT", details: urlError.localizedDescription)
            default:
                return SearchErrorPayload(
                    code: "BACKEND_REQUEST_FAILED",
                    details: urlError.localizedDescription,
                )
            }
        }

        return SearchErrorPayload(code: "QUERY_SEARCH_FAILED", details: String(describing: error))
    }
}

private enum QuerySearchError: Error {
    case backendURLMissing
    case backendURLInvalid(String)
    case backendResponseInvalid
    case backendDecodeFailed(String)
    case appliedFiltersMissing

    var payloadCode: String {
        switch self {
        case .backendURLMissing:
            "BACKEND_URL_MISSING"
        case .backendURLInvalid:
            "BACKEND_URL_INVALID"
        case .backendResponseInvalid:
            "BACKEND_RESPONSE_INVALID"
        case .backendDecodeFailed:
            "BACKEND_DECODE_FAILED"
        case .appliedFiltersMissing:
            "APPLIED_FILTERS_MISSING"
        }
    }

    var payloadDetails: String? {
        switch self {
        case .backendURLMissing, .backendResponseInvalid, .appliedFiltersMissing:
            nil
        case let .backendURLInvalid(rawValue):
            rawValue
        case let .backendDecodeFailed(details):
            details
        }
    }
}

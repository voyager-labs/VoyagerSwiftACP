import Foundation
import Logging

struct QuerySearchService: Sendable {
    private let searchService: MDQuerySearchService
    private let converter: QueryGatewayConverter
    private let logger: Logger

    init(
        searchService: MDQuerySearchService,
        logger: Logger = Logger(label: "VoyagerHelper.QuerySearchService"),
    ) {
        self.searchService = searchService
        self.logger = logger
        converter = QueryGatewayConverter(logger: Logger(label: "VoyagerHelper.QueryGatewayConverter"))
    }

    func querySearch(
        _ request: SearchRequestPayload,
    ) async throws -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return try await searchService.applyFilters(request.filters)
        }

        let conversion = await converter.convert(query: trimmedQuery, existingFilters: request.filters)

        if let llmError = conversion.error,
           llmError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            logger.warning("Gateway query interpretation failed: \(llmError)")
            return makeErrorResponse(
                code: "LLM_CONVERSION_FAILED",
                details: llmError,
                fallbackFilters: request.filters,
            )
        }

        let plannedFilters = SearchFiltersPayload(
            scopes: conversion.scopes ?? request.filters.scopes,
            conditions: conversion.conditions,
        )

        do {
            return try await searchService.applyFilters(plannedFilters)
        } catch {
            logger.warning("Local query execution failed: \(error)")
            return makeErrorResponse(
                code: "QUERY_SEARCH_FAILED",
                details: String(describing: error),
                fallbackFilters: plannedFilters,
            )
        }
    }

    private func makeErrorResponse(
        code: String,
        details: String?,
        fallbackFilters: SearchFiltersPayload,
    ) -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: fallbackFilters.scopes,
                conditions: fallbackFilters.conditions,
            ),
            items: [],
            error: SearchErrorPayload(code: code, details: details),
        )
    }
}

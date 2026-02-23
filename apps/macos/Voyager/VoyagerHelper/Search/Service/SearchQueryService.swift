import Foundation
import Logging

struct SearchQueryService: Sendable {
    private let searchService: SpotlightSearchService
    private let converter: GatewayQueryConverter
    private let logger: Logger

    init(
        searchService: SpotlightSearchService,
        converter: GatewayQueryConverter = GatewayQueryConverter(
            logger: Logger(label: "VoyagerHelper.GatewayQueryConverter"),
        ),
        logger: Logger = Logger(label: "VoyagerHelper.SearchQueryService"),
    ) {
        self.searchService = searchService
        self.converter = converter
        self.logger = logger
    }

    nonisolated func querySearch(
        _ request: SearchRequestPayload,
    ) async throws -> SearchResponsePayload {
        await convertQuery(request)
    }

    nonisolated func convertQuery(
        _ request: SearchRequestPayload,
    ) async -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return SearchResponsePayload(
                itemCount: 0,
                appliedFilters: AppliedFiltersPayload(
                    scopes: request.filters.scopes,
                    conditions: request.filters.conditions,
                ),
                items: nil,
                error: nil,
            )
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

        return SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: plannedFilters.scopes,
                conditions: plannedFilters.conditions,
            ),
            items: nil,
            error: nil,
        )
    }

    nonisolated func executeQuery(
        _ filters: SearchFiltersPayload,
    ) async throws -> SearchResponsePayload {
        try await searchService.applyFilters(filters)
    }

    private nonisolated func makeErrorResponse(
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

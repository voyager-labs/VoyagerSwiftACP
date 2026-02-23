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

        let chipsScopes = cleanScopes(request.filters.scopes)
        let resolvedScopes = resolveScopes(
            queryScopes: conversion.scopes,
            chipsScopes: chipsScopes,
        )

        let plannedFilters = SearchFiltersPayload(
            scopes: resolvedScopes,
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

    private nonisolated func resolveScopes(
        queryScopes: [String]?,
        chipsScopes: [String],
    ) -> [String] {
        if let queryScopes {
            let cleanedQueryScopes = cleanScopes(queryScopes)
            if cleanedQueryScopes.isEmpty == false {
                return cleanedQueryScopes
            }
        }

        return chipsScopes
    }

    private nonisolated func cleanScopes(_ scopes: [String]) -> [String] {
        scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}

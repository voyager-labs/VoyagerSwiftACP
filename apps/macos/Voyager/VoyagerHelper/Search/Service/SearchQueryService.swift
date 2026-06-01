import Foundation
import Logging
import VoyagerShared

protocol SearchExecutionServicing: Sendable {
    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload
    func searchRecent(_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload
    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload
}

struct SearchQueryService: Sendable {
    private let searchService: any SearchExecutionServicing
    private let convertQuery: @Sendable (String, SearchFiltersPayload) async -> GatewayQueryResult
    private let logger: Logger

    init(
        searchService: any SearchExecutionServicing,
        converter: GatewayQueryConverter = GatewayQueryConverter(
            logger: Logger(label: "VoyagerHelper.GatewayQueryConverter"),
        ),
        logger: Logger = Logger(label: "VoyagerHelper.SearchQueryService"),
    ) {
        self.searchService = searchService
        convertQuery = { query, existingFilters in
            await converter.convert(query: query, existingFilters: existingFilters)
        }
        self.logger = logger
    }

    init(
        searchService: any SearchExecutionServicing,
        convertQuery: @Sendable @escaping (String, SearchFiltersPayload) async -> GatewayQueryResult,
        logger: Logger = Logger(label: "VoyagerHelper.SearchQueryService"),
    ) {
        self.searchService = searchService
        self.convertQuery = convertQuery
        self.logger = logger
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
                excludedScopes: fallbackFilters.excludedScopes,
                includeSubfolders: fallbackFilters.includeSubfolders,
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

    nonisolated func querySearch(
        _ request: SearchRequestPayload,
    ) async -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return SearchResponsePayload(
                itemCount: 0,
                appliedFilters: AppliedFiltersPayload(
                    scopes: request.filters.scopes,
                    excludedScopes: request.filters.excludedScopes,
                    includeSubfolders: request.filters.includeSubfolders,
                    conditions: request.filters.conditions,
                ),
                items: nil,
                error: nil,
            )
        }

        let conversion = await convertQuery(trimmedQuery, request.filters)

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
            excludedScopes: request.filters.excludedScopes,
            includeSubfolders: request.filters.includeSubfolders,
            conditions: conversion.conditions,
        )

        return SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: plannedFilters.scopes,
                excludedScopes: plannedFilters.excludedScopes,
                includeSubfolders: plannedFilters.includeSubfolders,
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
}

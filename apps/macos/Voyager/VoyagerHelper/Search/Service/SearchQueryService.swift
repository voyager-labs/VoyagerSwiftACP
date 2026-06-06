import Foundation
import Logging
import VoyagerShared

protocol SearchExecutionServicing: Sendable {
    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload
    func searchRecent(_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload
    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload
}

struct SearchQueryService {
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
            appliedFilters: fallbackAppliedFilters(from: fallbackFilters),
            items: [],
            error: SearchErrorPayload(code: code, details: details),
        )
    }

    private nonisolated func resolveScopes(
        queryScopes: [String]?,
        chipsScopes: [String],
    ) -> [String] {
        if let queryScopes {
            let normalizedQueryScopes = SearchScopeNormalizer.normalizeScopes(queryScopes)
            if normalizedQueryScopes.isEmpty == false {
                return normalizedQueryScopes
            }
        }

        return SearchScopeNormalizer.normalizeScopes(chipsScopes)
    }

    private nonisolated func fallbackAppliedFilters(from filters: SearchFiltersPayload) -> AppliedFiltersPayload {
        AppliedFiltersPayload(
            scopes: filters.scopes,
            excludedScopes: filters.excludedScopes,
            includeSubfolders: filters.includeSubfolders,
            includeDirectories: filters.includeDirectories,
            conditions: filters.conditions,
        )
    }

    nonisolated func querySearch(
        _ request: SearchRequestPayload,
    ) async -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return SearchResponsePayload(
                itemCount: 0,
                appliedFilters: fallbackAppliedFilters(from: request.filters),
                items: nil,
                error: nil,
                queryOutcome: .unchangedResult,
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

        let chipsScopes = SearchScopeNormalizer.normalizeScopes(request.filters.scopes)
        let resolvedScopes = resolveScopes(
            queryScopes: conversion.scopes,
            chipsScopes: chipsScopes,
        )

        let plannedFilters = SearchFiltersPayload(
            scopes: resolvedScopes,
            excludedScopes: request.filters.excludedScopes,
            includeSubfolders: request.filters.includeSubfolders,
            includeDirectories: request.filters.includeDirectories,
            conditions: conversion.conditions,
        )

        let successFilters: AppliedFiltersPayload = switch conversion.queryOutcome {
        case .fallbackReuse, .unchangedResult:
            fallbackAppliedFilters(from: request.filters)
        case .convertedChanged, nil:
            AppliedFiltersPayload(
                scopes: plannedFilters.scopes,
                excludedScopes: plannedFilters.excludedScopes,
                includeSubfolders: plannedFilters.includeSubfolders,
                includeDirectories: plannedFilters.includeDirectories,
                conditions: plannedFilters.conditions,
            )
        }

        return SearchResponsePayload(
            itemCount: 0,
            appliedFilters: successFilters,
            items: nil,
            error: nil,
            queryOutcome: conversion.queryOutcome,
        )
    }

    nonisolated func executeQuery(
        _ filters: SearchFiltersPayload,
    ) async throws -> SearchResponsePayload {
        try await searchService.applyFilters(filters)
    }
}

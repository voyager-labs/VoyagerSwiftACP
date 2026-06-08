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
    private let convertQuery: @Sendable (String, SearchFiltersPayload) async -> QueryConversionResult
    private let logger: Logger

    init(
        searchService: any SearchExecutionServicing,
        converter: ProviderAwareQueryConverter = ProviderAwareQueryConverter(
            queryConversionInterpreter: QueryConversionInterpreter(
                logger: Logger(label: "VoyagerHelper.QueryConversionInterpreter"),
            ),
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
        convertQuery: @Sendable @escaping (String, SearchFiltersPayload) async -> QueryConversionResult,
        logger: Logger = Logger(label: "VoyagerHelper.SearchQueryService"),
    ) {
        self.searchService = searchService
        self.convertQuery = convertQuery
        self.logger = logger
    }

    nonisolated func querySearch(
        _ request: SearchRequestPayload,
    ) async -> SearchResponsePayload {
        let trimmedQuery = request.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty == false else {
            return Self.emptyQueryResponse(filters: request.filters)
        }

        let conversion = await convertQuery(trimmedQuery, request.filters)

        if let errorResponse = conversionErrorResponse(conversion, fallbackFilters: request.filters) {
            return errorResponse
        }

        let plannedFilters = plannedFilters(conversion: conversion, baselineFilters: request.filters)
        let finalOutcome = finalizedOutcome(
            conversion: conversion,
            plannedFilters: plannedFilters,
            baselineFilters: normalizedBaselineFilters(request.filters),
        )

        return Self.successResponse(
            filters: plannedFilters,
            queryConversion: queryConversionMetadata(for: conversion, outcome: finalOutcome),
        )
    }

    nonisolated func executeQuery(
        _ filters: SearchFiltersPayload,
    ) async throws -> SearchResponsePayload {
        try await searchService.applyFilters(filters)
    }

    nonisolated private func conversionErrorResponse(
        _ conversion: QueryConversionResult,
        fallbackFilters: SearchFiltersPayload,
    ) -> SearchResponsePayload? {
        guard let error = conversion.error?.trimmingCharacters(in: .whitespacesAndNewlines),
              error.isEmpty == false
        else {
            return nil
        }

        logger.warning("Query conversion interpretation failed: \(error)")
        return Self.errorResponse(
            code: conversion.errorCode ?? "LLM_CONVERSION_FAILED",
            details: error,
            fallbackFilters: fallbackFilters,
            queryConversion: queryConversionMetadata(for: conversion),
        )
    }

    nonisolated private func plannedFilters(
        conversion: QueryConversionResult,
        baselineFilters: SearchFiltersPayload,
    ) -> SearchFiltersPayload {
        SearchFiltersPayload(
            scopes: resolveScopes(
                queryScopes: conversion.scopes,
                chipsScopes: Self.cleanScopes(baselineFilters.scopes),
            ),
            excludedScopes: baselineFilters.excludedScopes,
            includeSubfolders: baselineFilters.includeSubfolders,
            conditions: conversion.conditions,
        )
    }
}

private extension SearchQueryService {
    nonisolated static func emptyQueryResponse(
        filters: SearchFiltersPayload,
    ) -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            items: nil,
            error: nil,
        )
    }

    nonisolated static func successResponse(
        filters: SearchFiltersPayload,
        queryConversion: SearchQueryConversionMetadataPayload,
    ) -> SearchResponsePayload {
        SearchResponsePayload(
            itemCount: 0,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            items: nil,
            error: nil,
            queryConversion: queryConversion,
        )
    }

    nonisolated static func errorResponse(
        code: String,
        details: String?,
        fallbackFilters: SearchFiltersPayload,
        queryConversion: SearchQueryConversionMetadataPayload? = nil,
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
            queryConversion: queryConversion,
        )
    }

    nonisolated static func cleanScopes(_ scopes: [String]) -> [String] {
        scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}

private extension SearchQueryService {
    nonisolated func queryConversionMetadata(
        for conversion: QueryConversionResult,
        outcome: QueryConversionResultOutcome? = nil,
    ) -> SearchQueryConversionMetadataPayload {
        SearchQueryConversionMetadataPayload(
            outcome: mapOutcome(outcome ?? conversion.outcome),
        )
    }

    nonisolated func mapOutcome(
        _ outcome: QueryConversionResultOutcome,
    ) -> SearchQueryConversionOutcomePayload {
        switch outcome {
        case .generatedChangeSet:
            .generatedChangeSet
        case .unchangedResult:
            .unchangedResult
        case .fallbackReuse:
            .fallbackReuse
        case .providerNotConfigured:
            .providerNotConfigured
        case .invalidCredential:
            .invalidCredential
        case .providerUnavailable:
            .providerUnavailable
        case .networkFailure:
            .networkFailure
        case .conversionFailure:
            .conversionFailure
        }
    }

    nonisolated func resolveScopes(
        queryScopes: [String]?,
        chipsScopes: [String],
    ) -> [String] {
        if let queryScopes {
            let cleanedQueryScopes = Self.cleanScopes(queryScopes)
            if cleanedQueryScopes.isEmpty == false {
                return cleanedQueryScopes
            }
        }

        return chipsScopes
    }

    nonisolated func normalizedBaselineFilters(_ filters: SearchFiltersPayload) -> SearchFiltersPayload {
        SearchFiltersPayload(
            scopes: Self.cleanScopes(filters.scopes),
            excludedScopes: filters.excludedScopes,
            includeSubfolders: filters.includeSubfolders,
            conditions: filters.conditions,
        )
    }

    nonisolated func finalizedOutcome(
        conversion: QueryConversionResult,
        plannedFilters: SearchFiltersPayload,
        baselineFilters: SearchFiltersPayload,
    ) -> QueryConversionResultOutcome {
        switch conversion.outcome {
        case .generatedChangeSet, .unchangedResult:
            plannedFilters == baselineFilters ? .unchangedResult : .generatedChangeSet
        case .fallbackReuse:
            plannedFilters == baselineFilters ? .fallbackReuse : .generatedChangeSet
        case .providerNotConfigured, .invalidCredential, .providerUnavailable, .networkFailure, .conversionFailure:
            conversion.outcome
        }
    }
}

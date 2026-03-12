import Foundation
import Logging

struct SpotlightSearchService: Sendable {
    private let logger: Logger
    private let maxCandidates: Int
    private let defaultScopeURL: @Sendable () -> URL
    private let executionEngine: SpotlightQueryEngine
    private let rewriteEngine: NSURLScopeRewriteEngine
    private let compilerTask: Task<SpotlightQueryCompiler, Error>

    enum SearchError: Error, LocalizedError {
        case queryCreationFailed
        case queryExecutionFailed

        var errorDescription: String? {
            switch self {
            case .queryCreationFailed:
                "MDQuery creation failed"
            case .queryExecutionFailed:
                "MDQuery execution failed"
            }
        }
    }

    init(
        logger: Logger = Logger(label: "VoyagerHelper.SpotlightSearchService"),
        maxCandidates: Int = 20000,
        defaultScopeURL: @Sendable @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        compilerFactory: @Sendable @escaping () async throws -> SpotlightQueryCompiler = {
            try SpotlightQueryCompiler()
        },
    ) {
        self.logger = logger
        self.maxCandidates = max(1, maxCandidates)
        self.defaultScopeURL = defaultScopeURL
        executionEngine = SpotlightQueryEngine(maxCandidates: self.maxCandidates)
        rewriteEngine = NSURLScopeRewriteEngine()
        compilerTask = Task(priority: .utility) {
            try await compilerFactory()
        }
    }

    private func resolveScopeURLs(_ scopes: [String]) -> [URL] {
        let normalized = SearchScopeNormalizer.normalizeScopes(scopes)
        if normalized.isEmpty {
            return [defaultScopeURL().standardizedFileURL]
        }
        return normalized.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        let requestId = UUID().uuidString
        let prepared = rewriteEngine.prepare(filters)

        let compiler = try await compilerTask.value
        let compiledPlan = try compiler.compilePlan(conditions: prepared.conditions)

        let scopeURLs = resolveScopeURLs(prepared.scopes)
        let paths = try executionEngine.loadPaths(
            queryString: compiledPlan.predicate,
            scopes: scopeURLs,
        )

        if paths.count == maxCandidates {
            logger.warning("MDQuery result truncated at maxCandidates=\(maxCandidates): id=\(requestId)")
        }

        let items = makeJSONItems(from: paths)

        logger.info(
            "MDQuery applyFilters completed: id=\(requestId) scopes=\(scopeURLs.count) pushdown_conditions=\(compiledPlan.pushdownConditions.count) items=\(items.count)",
        )

        return SearchResponsePayload(
            itemCount: items.count,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                conditions: filters.conditions,
            ),
            items: items,
            error: nil,
        )
    }
}

private extension SpotlightSearchService {
    func makeJSONItems(from paths: [String]) -> [JSONValue] {
        var items: [JSONValue] = []
        items.reserveCapacity(paths.count)

        for path in paths {
            items.append(.string(path))
        }

        return items
    }
}

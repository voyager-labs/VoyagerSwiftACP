import Foundation
import Logging

struct SpotlightSearchService: Sendable {
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

    private let logger: Logger
    private let maxCandidates: Int
    private let defaultScopeURL: @Sendable () -> URL
    private let executionEngine: SpotlightQueryEngine
    private let compilerTask: Task<SpotlightQueryCompiler, Error>
    private let postFilterTask: Task<PostFilterEvaluator, Error>

    private struct PlanExecutionResult {
        var plan: SpotlightQueryCompiler.CompilePlan
        let paths: [String]
        let usedFallback: Bool
    }

    init(
        logger: Logger = Logger(label: "VoyagerHelper.SpotlightSearchService"),
        maxCandidates: Int = 20000,
        defaultScopeURL: @Sendable @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        compilerFactory: @Sendable @escaping () async throws -> SpotlightQueryCompiler = {
            try SpotlightQueryCompiler()
        },
        postFilterFactory: @Sendable @escaping () async throws -> PostFilterEvaluator = {
            try PostFilterEvaluator()
        },
    ) {
        self.logger = logger
        self.maxCandidates = max(1, maxCandidates)
        self.defaultScopeURL = defaultScopeURL
        executionEngine = SpotlightQueryEngine(maxCandidates: self.maxCandidates)
        compilerTask = Task(priority: .utility) {
            try await compilerFactory()
        }
        postFilterTask = Task(priority: .utility) {
            try await postFilterFactory()
        }
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        let requestId = UUID().uuidString

        let compiler = try await compilerTask.value
        let postFilter = try await postFilterTask.value
        let compiledPlan = try compiler.compilePlan(conditions: filters.conditions)

        let scopeURLs = resolveScopeURLs(filters.scopes)
        let execution = try executePlan(
            compiledPlan,
            filters: filters,
            scopeURLs: scopeURLs,
            requestId: requestId,
        )

        let plan = execution.plan
        var paths = execution.paths

        if plan.postFilterConditions.isEmpty == false {
            paths = try postFilter.filter(paths: paths, conditions: plan.postFilterConditions)
        }

        if paths.count == maxCandidates {
            logger.warning("MDQuery result truncated at maxCandidates=\(maxCandidates): id=\(requestId)")
        }

        let items = makeJSONItems(from: paths)

        logger.info(
            "MDQuery applyFilters completed: id=\(requestId) scopes=\(scopeURLs.count) pushdown_conditions=\(plan.pushdownConditions.count) postfilter_conditions=\(plan.postFilterConditions.count) items=\(items.count) fallback=\(execution.usedFallback)",
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

    private func executePlan(
        _ initialPlan: SpotlightQueryCompiler.CompilePlan,
        filters: SearchFiltersPayload,
        scopeURLs: [URL],
        requestId: String,
    ) throws -> PlanExecutionResult {
        do {
            let paths = try executionEngine.loadPaths(
                queryString: initialPlan.predicate,
                scopes: scopeURLs,
            )

            return PlanExecutionResult(
                plan: initialPlan,
                paths: paths,
                usedFallback: false,
            )
        } catch let error as SearchError {
            guard initialPlan.pushdownConditions.isEmpty == false else {
                throw error
            }

            logger.warning(
                "MDQuery pushdown failed. Falling back to post-filter mode: id=\(requestId) error=\(error.localizedDescription)",
            )

            let paths = try executionEngine.loadPaths(
                queryString: SpotlightQueryCompiler.basePredicate,
                scopes: scopeURLs,
            )

            return PlanExecutionResult(
                plan: SpotlightQueryCompiler.CompilePlan(
                    predicate: SpotlightQueryCompiler.basePredicate,
                    pushdownConditions: [],
                    postFilterConditions: filters.conditions,
                ),
                paths: paths,
                usedFallback: true,
            )
        }
    }

    private func resolveScopeURLs(_ scopes: [String]) -> [URL] {
        let normalized = SearchScopeNormalizer.normalizeScopes(scopes)
        if normalized.isEmpty {
            return [defaultScopeURL().standardizedFileURL]
        }
        return normalized.map { URL(fileURLWithPath: $0).standardizedFileURL }
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

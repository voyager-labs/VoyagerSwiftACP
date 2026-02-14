@preconcurrency import CoreServices
import Foundation
import Logging

struct MDQuerySearchService: Sendable {
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
    private let compilerFactory: @Sendable () async throws -> FilterSearchMDQueryCompiler
    private let postFilterFactory: @Sendable () async throws -> FilterSearchMDQueryPostFilterEvaluator

    init(
        logger: Logger = Logger(label: "VoyagerHelper.MDQuerySearchService"),
        maxCandidates: Int = 20000,
        defaultScopeURL: @Sendable @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
        compilerFactory: @Sendable @escaping () async throws -> FilterSearchMDQueryCompiler = {
            try await MainActor.run {
                try FilterSearchMDQueryCompiler()
            }
        },
        postFilterFactory: @Sendable @escaping () async throws -> FilterSearchMDQueryPostFilterEvaluator = {
            try await MainActor.run {
                try FilterSearchMDQueryPostFilterEvaluator()
            }
        },
    ) {
        self.logger = logger
        self.maxCandidates = max(1, maxCandidates)
        self.defaultScopeURL = defaultScopeURL
        self.compilerFactory = compilerFactory
        self.postFilterFactory = postFilterFactory
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        let compiler = try await compilerFactory()
        var plan = try compiler.compilePlan(conditions: filters.conditions)
        let postFilter = try await postFilterFactory()
        let scopeURLs = Self.resolveScopeURLs(filters.scopes, defaultScopeURL: defaultScopeURL)
        var paths: [String]

        do {
            let query = try makeQuery(queryString: plan.predicate, scopes: scopeURLs)
            paths = loadPaths(query: query, limit: maxCandidates)
        } catch let error as SearchError {
            guard plan.pushdownConditions.isEmpty == false else {
                throw error
            }

            logger.warning(
                "MDQuery pushdown failed. Falling back to post-filter mode: \(error.localizedDescription)",
            )
            let fallbackQuery = try makeQuery(queryString: FilterSearchMDQueryCompiler.basePredicate, scopes: scopeURLs)
            paths = loadPaths(query: fallbackQuery, limit: maxCandidates)
            plan = FilterSearchMDQueryCompiler.CompilePlan(
                predicate: FilterSearchMDQueryCompiler.basePredicate,
                pushdownConditions: [],
                postFilterConditions: filters.conditions,
            )
        }

        if plan.postFilterConditions.isEmpty == false {
            paths = try postFilter.filter(paths: paths, conditions: plan.postFilterConditions)
        }

        if paths.count == maxCandidates {
            logger.warning("MDQuery result truncated at maxCandidates=\(maxCandidates)")
        }

        let items = paths.map(JSONValue.string)
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

    private func makeQuery(queryString: String, scopes: [URL]) throws -> MDQuery {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw SearchError.queryCreationFailed
        }
        let scopeRefs = scopes.map { $0 as CFURL } as CFArray
        MDQuerySetSearchScope(query, scopeRefs, 0)

        let executed = MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        guard executed else {
            throw SearchError.queryExecutionFailed
        }
        return query
    }

    private func loadPaths(query: MDQuery, limit: Int) -> [String] {
        let resultCount = Int(MDQueryGetResultCount(query))
        let upperBound = min(resultCount, limit)

        var seen: Set<String> = []
        var paths: [String] = []
        paths.reserveCapacity(upperBound)

        for index in 0 ..< upperBound {
            guard let item = MDQueryGetResultAtIndex(query, index) else {
                continue
            }
            let mdItem = unsafeBitCast(item, to: MDItem.self)
            guard let rawPath = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else {
                continue
            }

            let standardizedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            if isDirectory(mdItem: mdItem, path: standardizedPath) {
                continue
            }
            guard seen.insert(standardizedPath).inserted else {
                continue
            }
            paths.append(standardizedPath)
        }

        return paths.sorted()
    }

    static func resolveScopeURLs(
        _ scopes: [String],
        defaultScopeURL: @Sendable () -> URL,
    ) -> [URL] {
        let normalized = normalizeScopes(scopes)
        if normalized.isEmpty {
            return [defaultScopeURL().standardizedFileURL]
        }
        return normalized.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    static func normalizeScopes(_ scopes: [String]) -> [String] {
        FilterSearchScopeBuilder.normalizeScopes(scopes)
    }

    private func isDirectory(mdItem: MDItem, path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return true
        }

        if let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String,
           contentType == "public.folder"
        {
            return true
        }
        if let contentTypeTree = MDItemCopyAttribute(mdItem, kMDItemContentTypeTree) as? [String],
           contentTypeTree.contains("public.folder")
        {
            return true
        }
        if let fileKind = MDItemCopyAttribute(mdItem, kMDItemKind) as? String {
            let lowered = fileKind.lowercased()
            if lowered.contains("folder") || lowered.contains("directory") {
                return true
            }
        }
        return false
    }
}

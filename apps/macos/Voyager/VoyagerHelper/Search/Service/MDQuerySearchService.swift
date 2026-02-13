@preconcurrency import CoreServices
import Foundation
import Logging

struct MDQuerySearchService: Sendable {
    enum SearchError: Error, LocalizedError {
        case conditionsNotSupportedYet
        case queryCreationFailed
        case queryExecutionFailed

        var errorDescription: String? {
            switch self {
            case .conditionsNotSupportedYet:
                "MDQuery adapter does not support conditions yet"
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

    init(
        logger: Logger = Logger(label: "VoyagerHelper.MDQuerySearchService"),
        maxCandidates: Int = 20000,
        defaultScopeURL: @Sendable @escaping () -> URL = { FileManager.default.homeDirectoryForCurrentUser },
    ) {
        self.logger = logger
        self.maxCandidates = max(1, maxCandidates)
        self.defaultScopeURL = defaultScopeURL
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        guard filters.conditions.isEmpty else {
            throw SearchError.conditionsNotSupportedYet
        }

        let scopeURLs = Self.resolveScopeURLs(filters.scopes, defaultScopeURL: defaultScopeURL)
        let query = try makeQuery(scopes: scopeURLs)
        let paths = loadPaths(query: query, limit: maxCandidates)
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

    private func makeQuery(scopes: [URL]) throws -> MDQuery {
        let queryString = "kMDItemContentTypeTree == \"public.item\""
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

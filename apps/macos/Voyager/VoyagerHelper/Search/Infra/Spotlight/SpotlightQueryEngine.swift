@preconcurrency import CoreServices
import Foundation

struct SpotlightQueryEngine: Sendable {
    private let maxCandidates: Int

    init(maxCandidates: Int) {
        self.maxCandidates = max(1, maxCandidates)
    }

    func loadPaths(queryString: String, scopes: [URL]) throws -> [String] {
        let query = try makeQuery(queryString: queryString, scopes: scopes)
        return loadPaths(query: query, limit: maxCandidates)
    }
}

private extension SpotlightQueryEngine {
    func makeQuery(queryString: String, scopes: [URL]) throws -> MDQuery {
        guard let query = MDQueryCreate(kCFAllocatorDefault, queryString as CFString, nil, nil) else {
            throw SpotlightSearchService.SearchError.queryCreationFailed
        }
        let scopeRefs = scopes.map { $0 as CFURL } as CFArray
        MDQuerySetSearchScope(query, scopeRefs, 0)

        let executed = MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        guard executed else {
            throw SpotlightSearchService.SearchError.queryExecutionFailed
        }
        return query
    }

    func loadPaths(query: MDQuery, limit: Int) -> [String] {
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

        return paths
    }

    func isDirectory(mdItem: MDItem, path: String) -> Bool {
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

        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            return true
        }

        return false
    }
}

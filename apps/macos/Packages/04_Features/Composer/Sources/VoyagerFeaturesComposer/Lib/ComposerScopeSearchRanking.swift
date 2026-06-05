import Foundation

enum ComposerScopeSearchRanking {
    private enum SearchMatchRank: Int {
        case exact
        case prefix
        case wordBoundary
        case substring
    }

    private struct SearchResultScore {
        let rank: SearchMatchRank
        let substringIndex: Int
        let nameLength: Int
        let pathDepth: Int
        let normalizedName: String
        let normalizedPath: String

        nonisolated func precedes(_ other: SearchResultScore) -> Bool {
            if rank != other.rank { return rank.rawValue < other.rank.rawValue }
            if substringIndex != other.substringIndex { return substringIndex < other.substringIndex }
            if nameLength != other.nameLength { return nameLength < other.nameLength }
            if pathDepth != other.pathDepth { return pathDepth < other.pathDepth }
            if normalizedName != other.normalizedName { return normalizedName < other.normalizedName }
            return normalizedPath < other.normalizedPath
        }
    }

    nonisolated static func sort(
        _ results: [ComposerScopeUtils.DirectoryItem],
        query: String,
    ) -> [ComposerScopeUtils.DirectoryItem] {
        results.sorted { item1, item2 in
            searchResultScore(for: item1, query: query).precedes(searchResultScore(for: item2, query: query))
        }
    }

    nonisolated private static func searchResultScore(
        for item: ComposerScopeUtils.DirectoryItem,
        query: String,
    ) -> SearchResultScore {
        let normalizedName = item.name.lowercased()
        let normalizedPath = item.path.lowercased()
        let substringIndex = normalizedName.distance(
            from: normalizedName.startIndex,
            to: normalizedName.range(of: query)?.lowerBound ?? normalizedName.endIndex,
        )

        return SearchResultScore(
            rank: searchMatchRank(name: normalizedName, query: query),
            substringIndex: substringIndex,
            nameLength: normalizedName.count,
            pathDepth: pathDepth(item.path),
            normalizedName: normalizedName,
            normalizedPath: normalizedPath,
        )
    }

    nonisolated private static func searchMatchRank(
        name: String,
        query: String,
    ) -> SearchMatchRank {
        if name == query { return .exact }
        if name.hasPrefix(query) { return .prefix }
        if containsWordBoundaryMatch(name: name, query: query) { return .wordBoundary }
        return .substring
    }

    nonisolated private static func containsWordBoundaryMatch(
        name: String,
        query: String,
    ) -> Bool {
        var searchStart = name.startIndex

        while let range = name.range(of: query, range: searchStart ..< name.endIndex) {
            if range.lowerBound == name.startIndex {
                return true
            }

            let previousIndex = name.index(before: range.lowerBound)
            let previousCharacter = name[previousIndex]
            if !previousCharacter.isLetter, !previousCharacter.isNumber {
                return true
            }

            searchStart = range.upperBound
        }

        return false
    }

    nonisolated private static func pathDepth(_ path: String) -> Int {
        URL(fileURLWithPath: path).pathComponents.count
    }
}

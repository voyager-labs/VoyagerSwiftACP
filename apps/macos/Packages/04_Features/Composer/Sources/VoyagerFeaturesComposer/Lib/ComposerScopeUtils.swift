import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerShared

public enum ComposerScopeUtils {
    public struct DirectoryItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let path: String
        public let name: String
        public let iconName: String
        public let locationIdentifier: String?
        public let secondaryText: String?

        nonisolated public init(
            id: String,
            path: String,
            name: String,
            iconName: String,
            locationIdentifier: String? = nil,
            secondaryText: String? = nil,
        ) {
            self.id = id
            self.path = path
            self.name = name
            self.iconName = iconName
            self.locationIdentifier = locationIdentifier
            self.secondaryText = secondaryText
        }
    }

    private struct DirectoryMatchContext {
        let query: String
        let maxResults: Int
        let candidateLimit: Int
        let homePath: String
        let iconPathMap: [String: String]
    }

    private struct SearchExecutionContext {
        let match: DirectoryMatchContext
        let maxDepth: Int
        let startTime: Date
        let timeout: TimeInterval
        let resourceKeys: [URLResourceKey]
        let resourceKeySet: Set<URLResourceKey>
        let options: FileManager.DirectoryEnumerationOptions
    }

    nonisolated public static let rootScopePath = "/"

    nonisolated static func applyCandidateDisambiguationPolicy(_ items: [DirectoryItem]) -> [DirectoryItem] {
        let groups = Dictionary(grouping: items.enumerated(), by: { $0.element.name })
        let secondaryTextByID = groups.reduce(into: [String: String]()) { partialResult, group in
            let entries = group.value
            guard entries.count > 1 else { return }

            let duplicateItems = entries.map(\.element)
            let disambiguationTexts = ComposerScopeCandidateDisambiguation.texts(for: duplicateItems)
            for (entry, secondaryText) in zip(entries, disambiguationTexts) {
                partialResult[entry.element.id] = secondaryText
            }
        }

        return items.map { item in
            DirectoryItem(
                id: item.id,
                path: item.path,
                name: item.name,
                iconName: item.iconName,
                locationIdentifier: item.locationIdentifier,
                secondaryText: secondaryTextByID[item.id],
            )
        }
    }

    nonisolated static func searchDirectories(
        query: String,
        entryLoadingClient: EntryLoadingClient,
        maxResults: Int = 50,
        initialMaxDepth: Int = 2,
        timeout: TimeInterval = 2.0,
    ) async throws -> [DirectoryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryLower = normalizedQuery.lowercased()
        let candidateLimit = max(maxResults, maxResults * 4)
        let homeDir = entryLoadingClient.homeDirectory()
        let context = SearchExecutionContext(
            match: DirectoryMatchContext(
                query: queryLower,
                maxResults: maxResults,
                candidateLimit: candidateLimit,
                homePath: homeDir,
                iconPathMap: ComposerScopeSearchIconResolver.buildPathMapping(entryLoadingClient: entryLoadingClient),
            ),
            maxDepth: initialMaxDepth,
            startTime: Date(),
            timeout: timeout,
            resourceKeys: [.isDirectoryKey],
            resourceKeySet: Set([.isDirectoryKey]),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        )

        let searchPaths = makeSearchPaths(homeDir: homeDir)
        let results = bfsSearchDirectories(
            searchPaths: searchPaths,
            context: context,
            entryLoadingClient: entryLoadingClient,
        )
        return Array(ComposerScopeSearchRanking.sort(results, query: queryLower).prefix(maxResults))
    }

    static func buildCombinedList(
        history: [String],
        favorites: [ScopeFavoriteItem],
        entryLoadingClient: EntryLoadingClient,
        maxCount: Int = 10,
    ) -> [DirectoryItem] {
        var result: [DirectoryItem] = []
        var seenPaths: Set<String> = []
        let homePath = entryLoadingClient.homeDirectory()
        let iconPathMap = ComposerScopeSearchIconResolver.buildPathMapping(entryLoadingClient: entryLoadingClient)

        let historyItems = history.reversed().prefix(maxCount)
        for path in historyItems {
            if (path as NSString).pathExtension.lowercased() == CollectionConstants.fileExtension { continue }
            guard !seenPaths.contains(path) else { continue }
            guard entryLoadingClient.fileExists(path) else { continue }

            let displayName = entryLoadingClient.displayName(path)
            let iconName = ComposerScopeSearchIconResolver.iconName(
                for: path,
                homePath: homePath,
                iconPathMap: iconPathMap,
            )

            let locationMetadata = ComposerScopeCandidateDisambiguation.locationMetadata(path: path)

            result.append(
                DirectoryItem(
                    id: path,
                    path: path,
                    name: displayName,
                    iconName: iconName,
                    locationIdentifier: locationMetadata.locationIdentifier,
                    secondaryText: locationMetadata.secondaryText,
                ),
            )

            seenPaths.insert(path)
        }

        let remainingSlots = maxCount - result.count
        if remainingSlots > 0 {
            for favorite in favorites.prefix(remainingSlots) {
                let path = favorite.url.path
                if favorite.url.pathExtension.lowercased() == CollectionConstants.fileExtension { continue }
                guard !seenPaths.contains(path) else { continue }
                guard entryLoadingClient.fileExists(path) else { continue }

                let locationMetadata = ComposerScopeCandidateDisambiguation.locationMetadata(path: path)

                result.append(
                    DirectoryItem(
                        id: path,
                        path: path,
                        name: favorite.name,
                        iconName: favorite.iconName,
                        locationIdentifier: locationMetadata.locationIdentifier,
                        secondaryText: locationMetadata.secondaryText,
                    ),
                )

                seenPaths.insert(path)
            }
        }

        return result
    }

    nonisolated private static func isTraversalExcluded(_ path: String, currentDepth: Int) -> Bool {
        if currentDepth == 0 {
            let systemPrefixes = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/var"]
            if systemPrefixes.contains(where: { path.hasPrefix($0) }) {
                return true
            }
        }

        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(".") {
            return true
        }

        let excludedNames: Set = ["build", "DerivedData", "node_modules"]
        return excludedNames.contains(name)
    }

    nonisolated private static func processDirectoryItem(
        at fullPath: String,
        quickName: String,
        results: inout [DirectoryItem],
        context: DirectoryMatchContext,
        entryLoadingClient: EntryLoadingClient,
    ) {
        guard results.count < context.candidateLimit else { return }

        guard quickName.lowercased().contains(context.query) else { return }

        let displayName = entryLoadingClient.displayName(fullPath)

        let iconName = ComposerScopeSearchIconResolver.iconName(
            for: fullPath,
            homePath: context.homePath,
            iconPathMap: context.iconPathMap,
        )
        let locationMetadata = ComposerScopeCandidateDisambiguation.locationMetadata(path: fullPath)

        results.append(
            DirectoryItem(
                id: fullPath,
                path: fullPath,
                name: displayName,
                iconName: iconName,
                locationIdentifier: locationMetadata.locationIdentifier,
                secondaryText: locationMetadata.secondaryText,
            ),
        )
    }

    nonisolated private static func makeSearchPaths(homeDir: String) -> [String] {
        var searchPaths = [
            FileManager.default.currentDirectoryPath,
            homeDir,
            (homeDir as NSString).appendingPathComponent("Desktop"),
            (homeDir as NSString).appendingPathComponent("Documents"),
            (homeDir as NSString).appendingPathComponent("Downloads"),
        ]
        var seenSearchPaths = Set<String>()
        searchPaths = searchPaths.filter { seenSearchPaths.insert($0).inserted }
        return searchPaths
    }

    nonisolated private static func shouldStopSearch(
        resultsCount: Int,
        context: SearchExecutionContext,
    ) -> Bool {
        if Task.isCancelled { return true }
        if Date().timeIntervalSince(context.startTime) > context.timeout { return true }
        return resultsCount >= context.match.candidateLimit
    }

    nonisolated private static func shouldSkipNode(
        _ node: (path: String, depth: Int),
        seenPaths: inout Set<String>,
        context: SearchExecutionContext,
    ) -> Bool {
        if node.depth >= context.maxDepth { return true }
        if !seenPaths.insert(node.path).inserted { return true }
        return isTraversalExcluded(node.path, currentDepth: node.depth)
    }

    nonisolated private static func directoryContents(
        at path: String,
        entryLoadingClient: EntryLoadingClient,
        context: SearchExecutionContext,
    ) -> [URL]? {
        let pathURL = URL(fileURLWithPath: path, isDirectory: true)
        return try? entryLoadingClient.contentsOfDirectory(pathURL, context.resourceKeys, context.options)
    }

    nonisolated private static func processDirectoryContents(
        _ contents: [URL],
        currentDepth: Int,
        queue: inout [(path: String, depth: Int)],
        results: inout [DirectoryItem],
        context: SearchExecutionContext,
        entryLoadingClient: EntryLoadingClient,
    ) {
        for item in contents {
            if shouldStopSearch(resultsCount: results.count, context: context) {
                break
            }

            guard let values = try? item.resourceValues(forKeys: context.resourceKeySet),
                  values.isDirectory == true
            else {
                continue
            }

            let fullPath = item.path
            processDirectoryItem(
                at: fullPath,
                quickName: item.lastPathComponent,
                results: &results,
                context: context.match,
                entryLoadingClient: entryLoadingClient,
            )
            queue.append((fullPath, currentDepth + 1))
        }
    }

    nonisolated private static func bfsSearchDirectories(
        searchPaths: [String],
        context: SearchExecutionContext,
        entryLoadingClient: EntryLoadingClient,
    ) -> [DirectoryItem] {
        var queue: [(path: String, depth: Int)] = searchPaths.map { ($0, 0) }
        var cursor = 0
        var seenPaths = Set<String>()
        var results: [DirectoryItem] = []

        while cursor < queue.count {
            if shouldStopSearch(resultsCount: results.count, context: context) {
                break
            }

            let current = queue[cursor]
            cursor += 1

            if shouldSkipNode(current, seenPaths: &seenPaths, context: context) {
                continue
            }

            guard let contents = directoryContents(
                at: current.path,
                entryLoadingClient: entryLoadingClient,
                context: context,
            )
            else {
                continue
            }

            processDirectoryContents(
                contents,
                currentDepth: current.depth,
                queue: &queue,
                results: &results,
                context: context,
                entryLoadingClient: entryLoadingClient,
            )
        }

        return results
    }
}

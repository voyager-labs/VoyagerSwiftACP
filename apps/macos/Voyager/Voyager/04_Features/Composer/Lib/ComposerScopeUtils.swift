import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

enum ComposerScopeUtils {
    struct DirectoryItem: Identifiable, Equatable {
        let id: String
        let path: String
        let name: String
        let iconName: String
    }

    private struct IconMapping {
        let directory: FileManager.SearchPathDirectory
        let domain: FileManager.SearchPathDomainMask
        let iconName: String
    }

    private struct DirectoryMatchContext {
        let query: String
        let maxResults: Int
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

    static let rootScopePath = "/"

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
        let homeDir = entryLoadingClient.homeDirectory()
        let context = SearchExecutionContext(
            match: DirectoryMatchContext(
                query: queryLower,
                maxResults: maxResults,
                homePath: homeDir,
                iconPathMap: buildIconPathMapping(entryLoadingClient: entryLoadingClient),
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
        return Array(sortSearchResults(results, query: queryLower).prefix(maxResults))
    }

    static func buildCombinedList(
        history: [String],
        favorites: [ScopeFavoriteItem],
        entryLoadingClient: EntryLoadingClient,
        maxCount: Int = 10,
    ) -> [DirectoryItem] {
        var result: [DirectoryItem] = []
        var seenPaths: Set<String> = []
        let collectionsExtension = CollectionConstants.fileExtension
        let homePath = entryLoadingClient.homeDirectory()
        let iconPathMap = buildIconPathMapping(entryLoadingClient: entryLoadingClient)

        let historyItems = history.reversed().prefix(maxCount)
        for path in historyItems {
            if (path as NSString).pathExtension.lowercased() == collectionsExtension { continue }
            guard !seenPaths.contains(path) else { continue }
            guard entryLoadingClient.fileExists(path) else { continue }

            let displayName = entryLoadingClient.displayName(path)
            let iconName = iconNameForPath(path, homePath: homePath, iconPathMap: iconPathMap)

            result.append(
                DirectoryItem(
                    id: path,
                    path: path,
                    name: displayName,
                    iconName: iconName,
                ),
            )

            seenPaths.insert(path)
        }

        let remainingSlots = maxCount - result.count
        if remainingSlots > 0 {
            for favorite in favorites.prefix(remainingSlots) {
                let path = favorite.url.path
                if favorite.url.pathExtension.lowercased() == collectionsExtension { continue }
                guard !seenPaths.contains(path) else { continue }
                guard entryLoadingClient.fileExists(path) else { continue }

                result.append(
                    DirectoryItem(
                        id: path,
                        path: path,
                        name: favorite.name,
                        iconName: favorite.iconName,
                    ),
                )

                seenPaths.insert(path)
            }
        }

        return result
    }

    private nonisolated static func buildIconPathMapping(
        entryLoadingClient: EntryLoadingClient,
    ) -> [String: String] {
        let mappings: [IconMapping] = [
            IconMapping(directory: .applicationDirectory, domain: .localDomainMask, iconName: "folder.badge.gearshape"),
            IconMapping(directory: .desktopDirectory, domain: .userDomainMask, iconName: "menubar.dock.rectangle"),
            IconMapping(directory: .documentDirectory, domain: .userDomainMask, iconName: "doc.text"),
            IconMapping(directory: .downloadsDirectory, domain: .userDomainMask, iconName: "arrow.down.circle"),
            IconMapping(directory: .moviesDirectory, domain: .userDomainMask, iconName: "film"),
            IconMapping(directory: .musicDirectory, domain: .userDomainMask, iconName: "music.note"),
            IconMapping(directory: .picturesDirectory, domain: .userDomainMask, iconName: "photo"),
            IconMapping(directory: .trashDirectory, domain: .userDomainMask, iconName: "trash"),
        ]

        var pathMap: [String: String] = [:]
        for mapping in mappings {
            if let path = entryLoadingClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path {
                pathMap[path] = mapping.iconName
            }
        }

        return pathMap
    }

    private nonisolated static func iconNameForPath(
        _ path: String,
        homePath: String,
        iconPathMap: [String: String],
    ) -> String {
        if path == homePath { return "house" }
        if path.hasPrefix("/Volumes/") { return "externaldrive" }
        if let mapped = iconPathMap[path] { return mapped }

        return "folder"
    }

    private nonisolated static func isTraversalExcluded(_ path: String, currentDepth: Int) -> Bool {
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

        let excludedNames: Set<String> = ["build", "DerivedData", "node_modules"]
        return excludedNames.contains(name)
    }

    private nonisolated static func processDirectoryItem(
        at fullPath: String,
        quickName: String,
        results: inout [DirectoryItem],
        context: DirectoryMatchContext,
        entryLoadingClient: EntryLoadingClient,
    ) {
        guard results.count < context.maxResults else { return }

        guard quickName.lowercased().contains(context.query) else { return }

        let displayName = entryLoadingClient.displayName(fullPath)

        let iconName = iconNameForPath(
            fullPath,
            homePath: context.homePath,
            iconPathMap: context.iconPathMap,
        )
        results.append(
            DirectoryItem(
                id: fullPath,
                path: fullPath,
                name: displayName,
                iconName: iconName,
            ),
        )
    }

    private nonisolated static func sortSearchResults(
        _ results: [DirectoryItem],
        query: String,
    ) -> [DirectoryItem] {
        results.sorted { item1, item2 in
            let name1 = item1.name.lowercased()
            let name2 = item2.name.lowercased()

            let item1StartsWith = name1.hasPrefix(query)
            let item2StartsWith = name2.hasPrefix(query)

            if item1StartsWith != item2StartsWith {
                return item1StartsWith
            }

            return name1 < name2
        }
    }

    private nonisolated static func makeSearchPaths(homeDir: String) -> [String] {
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

    private nonisolated static func shouldStopSearch(
        resultsCount: Int,
        context: SearchExecutionContext,
    ) -> Bool {
        if Task.isCancelled { return true }
        if Date().timeIntervalSince(context.startTime) > context.timeout { return true }
        return resultsCount >= context.match.maxResults
    }

    private nonisolated static func shouldSkipNode(
        _ node: (path: String, depth: Int),
        seenPaths: inout Set<String>,
        context: SearchExecutionContext,
    ) -> Bool {
        if node.depth >= context.maxDepth { return true }
        if !seenPaths.insert(node.path).inserted { return true }
        return isTraversalExcluded(node.path, currentDepth: node.depth)
    }

    private nonisolated static func directoryContents(
        at path: String,
        entryLoadingClient: EntryLoadingClient,
        context: SearchExecutionContext,
    ) -> [URL]? {
        let pathURL = URL(fileURLWithPath: path, isDirectory: true)
        return try? entryLoadingClient.contentsOfDirectory(pathURL, context.resourceKeys, context.options)
    }

    private nonisolated static func processDirectoryContents(
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

    private nonisolated static func bfsSearchDirectories(
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

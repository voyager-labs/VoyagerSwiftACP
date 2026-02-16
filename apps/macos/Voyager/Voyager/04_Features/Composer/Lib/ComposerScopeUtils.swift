import Foundation

enum ComposerScopeUtils {
    static let rootScopePath = "/"

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

    private nonisolated static func iconNameForPath(_ path: String, entryLoadingClient: EntryLoadingClient)
        -> String
    {
        if path == entryLoadingClient.homeDirectory() { return "house" }
        if path.hasPrefix("/Volumes/") { return "externaldrive" }

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

        for mapping in mappings
            where entryLoadingClient.urlsForDirectory(mapping.directory, mapping.domain).first?.path == path
        {
            return mapping.iconName
        }

        return "folder"
    }

    private struct SearchParams {
        let query: String
        let maxResults: Int
        let maxDepth: Int
        let startTime: Date
        let timeout: TimeInterval
    }

    private nonisolated static func searchRecursive(
        at path: String,
        params: SearchParams,
        results: inout [DirectoryItem],
        currentDepth: Int,
        entryLoadingClient: EntryLoadingClient,
    ) {
        if Date().timeIntervalSince(params.startTime) > params.timeout {
            return
        }

        guard results.count < params.maxResults else { return }
        guard currentDepth < params.maxDepth else { return }

        // 시스템 디렉토리 제외 (성능 최적화)
        let systemPrefixes = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/var"]
        if currentDepth == 0, systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            return
        }

        guard let pathURL = URL(string: "file://\(path)"),
              let contents = try? entryLoadingClient.contentsOfDirectory(pathURL, [], [])
        else { return }

        for item in contents {
            if Date().timeIntervalSince(params.startTime) > params.timeout {
                return
            }

            guard results.count < params.maxResults else { break }

            let fullPath = (path as NSString).appendingPathComponent(item.path)
            var isDirectory: ObjCBool = false
            guard entryLoadingClient.fileExistsAtPath(fullPath, &isDirectory),
                  isDirectory.boolValue
            else { continue }

            processDirectoryItem(
                at: fullPath,
                query: params.query,
                results: &results,
                maxResults: params.maxResults,
                entryLoadingClient: entryLoadingClient,
            )

            searchRecursive(
                at: fullPath,
                params: params,
                results: &results,
                currentDepth: currentDepth + 1,
                entryLoadingClient: entryLoadingClient,
            )
        }
    }

    private nonisolated static func processDirectoryItem(
        at fullPath: String,
        query: String,
        results: inout [DirectoryItem],
        maxResults: Int,
        entryLoadingClient: EntryLoadingClient,
    ) {
        guard results.count < maxResults else { return }

        let displayName = entryLoadingClient.displayName(fullPath)
        let nameLower = displayName.lowercased()

        guard nameLower.contains(query) else { return }

        let iconName = iconNameForPath(fullPath, entryLoadingClient: entryLoadingClient)
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

    nonisolated static func searchDirectories(
        query: String,
        entryLoadingClient: EntryLoadingClient,
        maxResults: Int = 50,
        initialMaxDepth: Int = 2,
        timeout: TimeInterval = 2.0,
    ) async throws -> [DirectoryItem] {
        guard !query.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: [DirectoryItem].self) { group in
            let queryLower = query.lowercased()
            var allResults: [DirectoryItem] = []
            let startTime = Date()
            let homeDir = entryLoadingClient.homeDirectory()
            let searchPaths = [
                "/",
                homeDir,
                (homeDir as NSString).appendingPathComponent("Desktop"),
                (homeDir as NSString).appendingPathComponent("Documents"),
                (homeDir as NSString).appendingPathComponent("Downloads"),
            ]

            for searchPath in searchPaths {
                group.addTask {
                    await Task.yield()

                    var results: [DirectoryItem] = []
                    let params = SearchParams(
                        query: queryLower,
                        maxResults: maxResults,
                        maxDepth: initialMaxDepth,
                        startTime: startTime,
                        timeout: timeout,
                    )
                    searchRecursive(
                        at: searchPath,
                        params: params,
                        results: &results,
                        currentDepth: 0,
                        entryLoadingClient: entryLoadingClient,
                    )
                    return results
                }
            }

            for try await results in group {
                allResults.append(contentsOf: results)

                if Date().timeIntervalSince(startTime) > timeout {
                    break
                }

                if allResults.count >= maxResults {
                    group.cancelAll()
                    break
                }
            }

            return Array(sortSearchResults(allResults, query: queryLower).prefix(maxResults))
        }
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

        let historyItems = history.reversed().prefix(maxCount)
        for path in historyItems {
            if (path as NSString).pathExtension.lowercased() == collectionsExtension { continue }
            guard !seenPaths.contains(path) else { continue }
            guard entryLoadingClient.fileExists(path) else { continue }

            let displayName = entryLoadingClient.displayName(path)
            let iconName = iconNameForPath(path, entryLoadingClient: entryLoadingClient)

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
}

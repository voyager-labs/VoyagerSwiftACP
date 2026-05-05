import Foundation

enum ComposerScopeUtils {
    struct DirectoryItem: Identifiable, Equatable {
        let id: String
        let path: String
        let name: String
        let iconName: String
        let locationIdentifier: String?
        let secondaryText: String?

        nonisolated init(
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

    private struct CandidateDisambiguationSource {
        let parentPath: String
        let parentComponents: [String]
        let parentLastComponent: String
        let storageKindKey: String
        let storageLocationLabel: String?
    }

    nonisolated static let rootScopePath = "/"

    nonisolated static func candidateLocationMetadata(path: String)
        -> (locationIdentifier: String?, secondaryText: String?)
    {
        let normalizedPath = normalizeScopePath(path)
        guard normalizedPath != rootScopePath else {
            return (nil, nil)
        }

        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        let normalizedParentPath = normalizeScopePath(parentPath)
        guard normalizedParentPath != rootScopePath else {
            return (nil, nil)
        }

        return (normalizedParentPath, nil)
    }

    nonisolated static func applyCandidateDisambiguationPolicy(_ items: [DirectoryItem]) -> [DirectoryItem] {
        let groups = Dictionary(grouping: items.enumerated(), by: { $0.element.name })
        let secondaryTextByID = groups.reduce(into: [String: String]()) { partialResult, group in
            let entries = group.value
            guard entries.count > 1 else { return }

            let duplicateItems = entries.map(\.element)
            let disambiguationTexts = candidateDisambiguationTexts(for: duplicateItems)
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

            let locationMetadata = candidateLocationMetadata(path: path)

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
                if favorite.url.pathExtension.lowercased() == collectionsExtension { continue }
                guard !seenPaths.contains(path) else { continue }
                guard entryLoadingClient.fileExists(path) else { continue }

                let locationMetadata = candidateLocationMetadata(path: path)

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

    private nonisolated static func candidateDisambiguationTexts(for items: [DirectoryItem]) -> [String] {
        let sources = items.map { candidateDisambiguationSource(for: $0) }
        var disambiguationTexts = [String?](repeating: nil, count: sources.count)

        let groupedByParent = Dictionary(grouping: Array(sources.enumerated()), by: { $0.element.parentLastComponent })
        for entries in groupedByParent.values {
            guard let first = entries.first else { continue }
            if entries.count == 1, !first.element.parentLastComponent.isEmpty {
                disambiguationTexts[first.offset] = first.element.parentLastComponent
                continue
            }

            let clusterSources = entries.map(\.element)
            let assignedLabels = Set(disambiguationTexts.compactMap(\.self))

            if let labels = candidateDisambiguationLabels(
                for: clusterSources,
                existingLabels: assignedLabels,
            ) {
                for (entry, label) in zip(entries, labels) {
                    disambiguationTexts[entry.offset] = label
                }
                continue
            }

            for entry in entries {
                disambiguationTexts[entry.offset] = entry.element.parentPath
            }
        }

        return disambiguationTexts.map { $0 ?? "" }
    }

    private nonisolated static func candidateDisambiguationLabels(
        for sources: [CandidateDisambiguationSource],
        existingLabels: Set<String>,
    ) -> [String]? {
        if hasMixedStorageKinds(sources) {
            return uniqueStorageFallbackLabels(
                for: sources,
                existingLabels: existingLabels,
            )
        }

        if let suffixLabels = uniqueParentSuffixLabels(
            for: sources,
            existingLabels: existingLabels,
        ) {
            return suffixLabels
        }

        return nil
    }

    private nonisolated static func candidateDisambiguationSource(
        for item: DirectoryItem,
    ) -> CandidateDisambiguationSource {
        let parentPath = normalizedParentPath(for: item)
        let parentComponents = pathComponents(parentPath)
        let parentLastComponent = parentComponents.last ?? item.name
        let (storageKindKey, storageLocationLabel) = storageMetadata(parentComponents: parentComponents)

        return CandidateDisambiguationSource(
            parentPath: parentPath,
            parentComponents: parentComponents,
            parentLastComponent: parentLastComponent,
            storageKindKey: storageKindKey,
            storageLocationLabel: storageLocationLabel,
        )
    }

    private nonisolated static func normalizedParentPath(for item: DirectoryItem) -> String {
        if let locationIdentifier = item.locationIdentifier, !locationIdentifier.isEmpty {
            return normalizeScopePath(locationIdentifier)
        }

        let normalizedPath = normalizeScopePath(item.path)
        let parentPath = (normalizedPath as NSString).deletingLastPathComponent
        return normalizeScopePath(parentPath)
    }

    private nonisolated static func pathComponents(_ path: String) -> [String] {
        normalizeScopePath(path)
            .split(separator: Character(rootScopePath))
            .map(String.init)
    }

    private nonisolated static func storageMetadata(
        parentComponents: [String],
    ) -> (String, String?) {
        guard let firstComponent = parentComponents.first else {
            return ("other", nil)
        }

        if firstComponent == "Volumes", parentComponents.count >= 2 {
            return ("volume", parentComponents[1])
        }

        if firstComponent == "Users", parentComponents.count >= 2 {
            return ("userHome", parentComponents[1])
        }

        return ("other", firstComponent)
    }

    private nonisolated static func hasMixedStorageKinds(_ sources: [CandidateDisambiguationSource]) -> Bool {
        Set(sources.map(\.storageKindKey)).count > 1
    }

    private nonisolated static func uniqueParentSuffixLabels(
        for sources: [CandidateDisambiguationSource],
        existingLabels: Set<String>,
    ) -> [String]? {
        let maxDepth = sources.map(\.parentComponents.count).max() ?? 0
        guard maxDepth >= 2 else { return nil }

        for depth in 2 ... maxDepth {
            let labels = sources.map { parentSuffixLabel(for: $0, depth: depth) }
            let labelSet = Set(labels)
            guard labelSet.count == labels.count else { continue }
            guard existingLabels.isDisjoint(with: labelSet) else { continue }
            return labels
        }

        return nil
    }

    private nonisolated static func parentSuffixLabel(
        for source: CandidateDisambiguationSource,
        depth: Int,
    ) -> String {
        let suffixComponents = source.parentComponents.suffix(depth)
        if suffixComponents.isEmpty {
            return source.parentPath
        }

        return suffixComponents.joined(separator: rootScopePath)
    }

    private nonisolated static func uniqueStorageFallbackLabels(
        for sources: [CandidateDisambiguationSource],
        existingLabels: Set<String>,
    ) -> [String]? {
        let labels = sources.map { source -> String in
            let parentLabel = source.parentLastComponent.isEmpty ? source.parentPath : source.parentLastComponent
            let storageLabel = source.storageLocationLabel ?? source.parentPath
            return storageLabel + " • " + parentLabel
        }
        let labelSet = Set(labels)
        guard labelSet.count == labels.count else { return nil }
        guard existingLabels.isDisjoint(with: labelSet) else { return nil }
        return labels
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
        let locationMetadata = candidateLocationMetadata(path: fullPath)

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

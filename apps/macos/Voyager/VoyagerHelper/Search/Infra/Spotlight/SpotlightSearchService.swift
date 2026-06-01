import CoreServices
import Darwin
import Foundation
import ImageIO
import Logging
import UniformTypeIdentifiers
import VoyagerShared

struct SpotlightSearchService: Sendable, SearchExecutionServicing {
    private nonisolated static let userTagsXattrName = "com.apple.metadata:_kMDItemUserTags"
    private let logger: Logger
    private let maxCandidates: Int
    private let defaultScopeURL: @Sendable () -> URL
    private let rawUserTagsLoader: @Sendable (URL) -> [String]
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
        rawUserTagsLoader: @Sendable @escaping (URL) -> [String] = SpotlightSearchService.loadRawUserTags,
        compilerFactory: @Sendable @escaping () async throws -> SpotlightQueryCompiler = {
            try SpotlightQueryCompiler()
        },
    ) {
        self.logger = logger
        self.maxCandidates = max(1, maxCandidates)
        self.defaultScopeURL = defaultScopeURL
        self.rawUserTagsLoader = rawUserTagsLoader
        executionEngine = SpotlightQueryEngine(maxCandidates: self.maxCandidates)
        rewriteEngine = NSURLScopeRewriteEngine()
        compilerTask = Task(priority: .utility) {
            try await compilerFactory()
        }
    }

    func applyFilters(_ filters: SearchFiltersPayload) async throws -> SearchResponsePayload {
        let requestId = UUID().uuidString
        let prepared = rewriteEngine.prepare(filters)

        let compiler = try await compilerTask.value
        let compiledPlan = try compiler.compilePlan(conditions: prepared.conditions)

        let scopeURLs = resolveFilterScopeURLs(prepared.scopes)
        let normalizedFilterScopes = SearchScopeNormalizer.normalizeScopes(prepared.scopes)
        let paths: [String] = if filters.includeSubfolders || normalizedFilterScopes.isEmpty {
            try executionEngine.loadPaths(
                queryString: compiledPlan.predicate,
                scopes: scopeURLs,
                limit: maxCandidates,
            )
        } else {
            try executionEngine.loadPaths(
                queryString: compiledPlan.predicate,
                scopes: scopeURLs,
                limit: maxCandidates,
                shouldIncludePath: { path in
                    pathMatchesExactFolderScope(path, normalizedScopes: normalizedFilterScopes)
                },
            )
        }
        let filteredPaths = filterPaths(
            paths,
            scopes: prepared.scopes,
            includeSubfolders: filters.includeSubfolders,
            excludedScopes: filters.excludedScopes,
        )

        if paths.count == maxCandidates {
            logger.warning("MDQuery result truncated at maxCandidates=\(maxCandidates): id=\(requestId)")
        }

        let items = makeJSONItems(from: filteredPaths)

        logger.info(
            "MDQuery applyFilters completed: id=\(requestId) scopes=\(scopeURLs.count) pushdown_conditions=\(compiledPlan.pushdownConditions.count) items=\(items.count)",
        )

        return SearchResponsePayload(
            itemCount: items.count,
            appliedFilters: AppliedFiltersPayload(
                scopes: filters.scopes,
                excludedScopes: filters.excludedScopes,
                includeSubfolders: filters.includeSubfolders,
                conditions: filters.conditions,
            ),
            items: items,
            error: nil,
        )
    }

    func searchRecent(_ request: RecentSearchRequestPayload) async throws -> RecentSearchResponsePayload {
        let predicate = "kMDItemLastUsedDate > $time.today(-1000000)"
        let matches = try executionEngine.loadMatches(
            queryString: predicate,
            scopes: resolveMetadataScopeURLs(mode: request.scopeMode, scopes: request.scopes),
            limit: maxCandidates,
            excludeDirectories: true,
        )
        return makeRecentResponse(from: matches, request: request)
    }

    func searchTag(_ request: TagSearchRequestPayload) async throws -> TagSearchResponsePayload {
        let predicate = makeTagPredicate(for: request.requestedTag)
        let matches = try executionEngine.loadMatches(
            queryString: predicate,
            scopes: resolveMetadataScopeURLs(mode: request.scopeMode, scopes: request.scopes),
            limit: maxCandidates,
            excludeDirectories: false,
        )
        return makeTagResponse(from: matches, request: request)
    }
}

extension SpotlightSearchService {
    func makeRecentResponse(
        from matches: [SpotlightQueryEngine.QueryMatch],
        request: RecentSearchRequestPayload,
    ) -> RecentSearchResponsePayload {
        let sortedMatches = matches.sorted {
            ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast)
        }

        let items = sortedMatches
            .compactMap(makeEntryPayload)
            .filter { request.includeHidden || !$0.isHidden }

        return RecentSearchResponsePayload(items: Array(items.prefix(max(0, request.resultCap))))
    }

    func makeTagResponse(
        from matches: [SpotlightQueryEngine.QueryMatch],
        request: TagSearchRequestPayload,
    ) -> TagSearchResponsePayload {
        let sortedMatches = matches.sorted {
            ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast)
        }

        let items = sortedMatches
            .compactMap(makeEntryPayload)
            .filter { entry in
                guard request.includeHidden || !entry.isHidden else {
                    return false
                }

                guard request.exactTagVerification else {
                    return true
                }

                return entry.tags?.contains(where: {
                    $0.name.localizedCaseInsensitiveCompare(request.requestedTag) == .orderedSame
                }) == true
            }

        return TagSearchResponsePayload(
            requestedTag: request.requestedTag,
            items: Array(items.prefix(max(0, request.resultCap))),
        )
    }
}

extension SpotlightSearchService {
    func makeTagPredicate(for requestedTag: String) -> String {
        let escapedTag = requestedTag.replacingOccurrences(of: "\"", with: "\\\"")
        return "kMDItemUserTags == \"\(escapedTag)\"c || kMDItemUserTags == \"*\(escapedTag)*\"c"
    }

    func resolveFilterScopeURLs(_ scopes: [String]) -> [URL] {
        let normalized = SearchScopeNormalizer.normalizeScopes(scopes)
        if normalized.isEmpty {
            return [defaultScopeURL().standardizedFileURL]
        }
        return normalized.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    func resolveMetadataScopeURLs(mode: RecentTagSearchScopeModePayload, scopes: [String]) -> [URL]? {
        switch mode {
        case .allIndexed:
            return nil
        case .scopedPaths:
            let normalized = SearchScopeNormalizer.normalizeScopes(scopes)
            if normalized.isEmpty {
                return [defaultScopeURL().standardizedFileURL]
            }
            return normalized.map { URL(fileURLWithPath: $0).standardizedFileURL }
        }
    }

    func filterPaths(
        _ paths: [String],
        scopes: [String],
        includeSubfolders: Bool,
        excludedScopes: [String] = [],
    ) -> [String] {
        let normalizedScopes = SearchScopeNormalizer.normalizeScopes(scopes)
        let normalizedExcludedScopes = includeSubfolders
            ? SearchScopeNormalizer.normalizeScopes(excludedScopes)
            : []

        return paths.filter { path in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

            if includeSubfolders == false,
               normalizedScopes.isEmpty == false,
               pathMatchesExactFolderScope(normalizedPath, normalizedScopes: normalizedScopes) == false
            {
                return false
            }

            if normalizedExcludedScopes.contains(where: { pathIsDescendantOrEqual(normalizedPath, scope: $0) }) {
                return false
            }

            return true
        }
    }

    func pathMatchesExactFolderScope(_ path: String, normalizedScopes: [String]) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let parentPath = URL(fileURLWithPath: normalizedPath).deletingLastPathComponent().standardizedFileURL.path
        return normalizedScopes.contains(parentPath == "/" ? "/" : parentPath)
    }

    func pathIsDescendantOrEqual(_ path: String, scope: String) -> Bool {
        if path == scope {
            return true
        }

        let prefix = scope == "/" ? "/" : scope + "/"
        return path.hasPrefix(prefix)
    }

    func makeJSONItems(from paths: [String]) -> [JSONValue] {
        var items: [JSONValue] = []
        items.reserveCapacity(paths.count)

        for path in paths {
            items.append(.string(path))
        }

        return items
    }

    func makeEntryPayload(from match: SpotlightQueryEngine.QueryMatch) -> SearchEntryPayload? {
        let url = URL(fileURLWithPath: match.path)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: match.path, isDirectory: &isDirectory) else {
            return nil
        }

        let resourceValues = try? url.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .isHiddenKey,
        ])

        let name = resourceValues?.name ?? url.lastPathComponent
        let isHidden = (resourceValues?.isHidden ?? false) || name.hasPrefix(".")
        let tags = makeTags(from: match, url: url)

        return SearchEntryPayload(
            name: name,
            fullPath: match.path,
            isFolder: isDirectory.boolValue,
            isHidden: isHidden,
            size: Int64(resourceValues?.fileSize ?? 0),
            modifiedDate: resourceValues?.contentModificationDate ?? Date.distantPast,
            fileExtension: url.pathExtension,
            createdDate: resourceValues?.creationDate ?? Date.distantPast,
            addedDate: resourceValues?.addedToDirectoryDate ?? Date.distantPast,
            lastOpenedDate: match.lastUsedDate,
            kind: makeKind(url: url, isDirectory: isDirectory.boolValue),
            creatorApplication: makeCreatorApplicationName(for: url, isDirectory: isDirectory.boolValue),
            tags: tags,
            supplementaryMetadata: makeSupplementaryMetadata(url: url, isDirectory: isDirectory.boolValue),
        )
    }

    func makeTags(from match: SpotlightQueryEngine.QueryMatch, url: URL) -> [SearchTagPayload]? {
        let matchTags = match.rawUserTags.compactMap(parseTag)
        let shouldReloadRawTags = match.rawUserTags.isEmpty ||
            (match.rawUserTags.contains(where: { $0.contains("\n") }) == false &&
                matchTags.allSatisfy { $0.colorCode == 0 })

        guard shouldReloadRawTags else {
            return matchTags.isEmpty ? nil : matchTags
        }

        let reloadedTags = rawUserTagsLoader(url).compactMap(parseTag)
        guard reloadedTags.isEmpty == false else {
            return matchTags.isEmpty ? nil : matchTags
        }

        return reloadedTags.contains(where: { $0.colorCode != 0 }) || matchTags.isEmpty
            ? reloadedTags
            : matchTags
    }

    func parseTag(_ rawTag: String) -> SearchTagPayload? {
        let components = rawTag.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawName = components.first else {
            return nil
        }

        let name = String(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            return nil
        }

        let colorCode = if components.count == 2 {
            Int(String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        } else {
            0
        }

        return SearchTagPayload(name: name, colorCode: colorCode)
    }

    nonisolated static func loadRawUserTags(from url: URL) -> [String] {
        guard let tagData = loadRawUserTagsXattrData(from: url) else {
            return []
        }

        return (try? PropertyListSerialization.propertyList(from: tagData, format: nil) as? [String]) ?? []
    }

    private nonisolated static func loadRawUserTagsXattrData(from url: URL) -> Data? {
        let size = getxattr(url.path, userTagsXattrName, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else {
            return nil
        }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer in
            getxattr(
                url.path,
                userTagsXattrName,
                buffer.baseAddress,
                size,
                0,
                XATTR_NOFOLLOW,
            )
        }
        guard result >= 0 else {
            return nil
        }

        return data
    }

    func makeKind(url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return "Folder"
        }

        var kind = url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased() + " File"
        if let mdItem = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
           let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String
        {
            let type = UTType(importedAs: contentType)
            kind = type.localizedDescription ?? contentType
        }
        return kind
    }

    func makeCreatorApplicationName(for url: URL, isDirectory: Bool) -> String? {
        guard isDirectory == false else {
            return nil
        }

        guard let unmanaged = LSCopyDefaultApplicationURLForURL(url as CFURL, .all, nil) else {
            return nil
        }

        let appURL = unmanaged.takeRetainedValue() as URL
        return appURL.deletingPathExtension().lastPathComponent
    }

    func makeSupplementaryMetadata(url: URL, isDirectory: Bool) -> SearchEntrySupplementaryMetadataPayload? {
        if isDirectory {
            let ext = url.pathExtension.lowercased()
            guard ext != "voycoll" else {
                return nil
            }

            guard isPackageDirectory(url) == false else {
                return nil
            }

            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            ) else {
                return nil
            }
            return .folderItemCount(entries.count)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext),
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int
        {
            return .imageResolution(width: width, height: height)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext),
           let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        {
            return .compressedFileSize(Int64(fileSize))
        }

        return nil
    }

    func isPackageDirectory(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isPackageKey]),
           values.isPackage == true
        {
            return true
        }

        let ext = url.pathExtension.lowercased()
        if ["app", "icon"].contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .package)
        {
            return true
        }

        return false
    }
}

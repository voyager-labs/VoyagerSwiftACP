import Foundation

extension InitialIndexingRunner {
    static func collectDirectoryPaths(items: [IndexedItem]) -> Set<String> {
        var paths: Set<String> = []
        paths.reserveCapacity(items.count)
        for item in items {
            let standardizedPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
            if IndexingRecordBuilder.isDirectory(mdItem: item.mdItem, path: standardizedPath) {
                paths.insert(standardizedPath)
            } else {
                let dirPath = URL(fileURLWithPath: standardizedPath)
                    .deletingLastPathComponent()
                    .path
                paths.insert(dirPath)
            }
        }
        return paths
    }

    static func resolveDirectoryPaths(
        _ paths: Set<String>,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async {
        let sortedPaths = paths.sorted { $0.count < $1.count }
        for path in sortedPaths {
            _ = await resolveDirectoryIdLightweight(
                dirPath: path,
                homeURL: homeURL,
                cachedVolumeIdentifier: cachedVolumeIdentifier,
                directoryRepo: directoryRepo,
                directoryCache: &directoryCache,
            )
        }
    }
}

extension InitialIndexingRunner {
    static func resolveDirectoryIdLightweight(
        dirPath: String,
        homeURL: URL,
        cachedVolumeIdentifier: String?,
        directoryRepo: DirectoryRepository,
        directoryCache: inout [String: Int64],
    ) async -> Int64? {
        if let cached = directoryCache[dirPath] {
            return cached
        }

        let parentId = await resolveParentDirectoryId(
            dirPath: dirPath,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedVolumeIdentifier,
            directoryRepo: directoryRepo,
            directoryCache: &directoryCache,
        )
        let cachedIdentifier = dirPath.hasPrefix(homeURL.path) ? cachedVolumeIdentifier : nil
        guard var directoryRecord = IndexingRecordBuilder.makeLightweightDirectoryRecord(
            path: dirPath,
            homeURL: homeURL,
            cachedVolumeIdentifier: cachedIdentifier,
        ) else {
            return nil
        }
        directoryRecord.parentId = parentId
        return await upsertDirectoryRecord(
            dirPath: dirPath,
            directoryRecord: directoryRecord,
            directoryRepo: directoryRepo,
            directoryCache: &directoryCache,
        )
    }
}

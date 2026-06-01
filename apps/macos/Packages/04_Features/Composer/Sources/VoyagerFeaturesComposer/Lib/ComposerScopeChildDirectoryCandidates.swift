import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

enum ComposerScopeChildDirectoryCandidates {
    static func make(
        parentPath: String,
        entryLoadingClient: EntryLoadingClient,
        maxCount: Int = 50,
    ) -> [ComposerScopeUtils.DirectoryItem] {
        let normalizedParentPath = ComposerScopeUtils.normalizeScopePath(parentPath)
        let parentURL = URL(fileURLWithPath: normalizedParentPath, isDirectory: true)
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
        guard let contents = try? entryLoadingClient.contentsOfDirectory(
            parentURL,
            resourceKeys,
            [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else {
            return []
        }

        let collectionsExtension = CollectionConstants.fileExtension
        let items = contents.compactMap { url -> ComposerScopeUtils.DirectoryItem? in
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isDirectory == true
            else {
                return nil
            }

            let path = ComposerScopeUtils.normalizeScopePath(url.path)
            guard (path as NSString).pathExtension.lowercased() != collectionsExtension else {
                return nil
            }

            let locationMetadata = ComposerScopeCandidateDisambiguation.locationMetadata(path: path)

            return ComposerScopeUtils.DirectoryItem(
                id: path,
                path: path,
                name: entryLoadingClient.displayName(path),
                iconName: "folder",
                locationIdentifier: locationMetadata.locationIdentifier,
                secondaryText: locationMetadata.secondaryText,
            )
        }

        return Array(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(maxCount))
    }
}

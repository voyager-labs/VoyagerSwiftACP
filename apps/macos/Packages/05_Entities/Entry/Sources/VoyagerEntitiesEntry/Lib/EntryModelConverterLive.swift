import Foundation
import VoyagerEntitiesTag
import VoyagerShared

public enum EntryModelConverterLive {
    nonisolated public static func convertURLToEntry(
        _ itemURL: URL,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
    ) -> EntryModel? {
        guard var entry = convertURLToCoreEntry(itemURL, entryLoadingClient: entryLoadingClient) else {
            return nil
        }
        for probe in EntryMetadataProbe.allCases {
            if let patch = metadataPatch(
                for: entry,
                probe: probe,
                entryLoadingClient: entryLoadingClient,
                workspaceClient: workspaceClient,
            ) {
                entry = entry.applying(patch)
            }
        }
        return entry
    }

    nonisolated public static func convertURLToCoreEntry(
        _ itemURL: URL,
        entryLoadingClient: EntryLoadingClient,
    ) -> EntryModel? {
        convertURLToCoreEntry(itemURL, lexicalURL: itemURL, entryLoadingClient: entryLoadingClient)
    }

    nonisolated public static func metadataPatch(
        for entry: EntryModel,
        probe: EntryMetadataProbe,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
        favoriteTags: [Tag] = [],
        sourceURL: URL? = nil,
    ) -> EntryMetadataPatch? {
        let url = sourceURL ?? URL(fileURLWithPath: entry.fullPath)
        switch probe {
        case .spotlight:
            let metadata = entryLoadingClient.getItemMetadata(url, entry.isFolder, workspaceClient)
            return .spotlight(
                id: entry.id,
                kind: metadata.kind,
                creatorApplication: metadata.creatorApplication,
                lastOpenedDate: metadata.lastUsedDate,
            )
        case .tags:
            let patch = EntryMetadataPatch.tags(id: entry.id, tags: entryTags(from: url))
            let normalizedEntry = EntryModelTagColorNormalizer.normalize(
                entry.applying(patch),
                favoriteTags: favoriteTags,
            )
            return .tags(id: entry.id, tags: normalizedEntry.facets.tags)
        case .supplementaryMetadata:
            return .supplementaryMetadata(
                id: entry.id,
                metadata: entrySupplementaryMetadata(
                    url: url,
                    isDirectory: entry.isFolder,
                    entryLoadingClient: entryLoadingClient,
                ),
            )
        }
    }

    nonisolated static func convertURLToCoreEntry(
        _ sourceURL: URL,
        lexicalURL: URL,
        entryLoadingClient: EntryLoadingClient,
    ) -> EntryModel? {
        var isDirectory: ObjCBool = false
        guard entryLoadingClient.fileExistsAtPath(sourceURL.path, &isDirectory) else { return nil }
        let resourceValues = try? sourceURL.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
            .isHiddenKey,
        ])

        let name = resourceValues?.name ?? lexicalURL.lastPathComponent
        let size = Int64(resourceValues?.fileSize ?? 0)
        let modifiedDate = resourceValues?.contentModificationDate ?? Date()
        let createdDate = resourceValues?.creationDate ?? Date()
        let addedDate = resourceValues?.addedToDirectoryDate ?? Date()

        let isHidden = resourceValues?.isHidden ?? false || name.hasPrefix(".")
        let isPackage = isDirectory.boolValue && entryLoadingClient.isPackageDirectory(sourceURL)

        return EntryModel(
            name: name,
            fullPath: lexicalURL.path,
            isFolder: isDirectory.boolValue,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            fileExtension: lexicalURL.pathExtension,
            facets: EntryFacets(
                createdDate: createdDate,
                addedDate: addedDate,
                lastOpenedDate: nil,
                kind: isDirectory.boolValue ? "Folder" : lexicalURL.pathExtension.isEmpty ? "File" : lexicalURL
                    .pathExtension
                    .uppercased() + " File",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
            isPackage: isPackage,
        )
    }

    nonisolated private static func entryTags(from itemURL: URL) -> [Tag]? {
        if let tags = TagMetadataClient.loadTags(from: itemURL) {
            return tags
        }

        if let tagNames = try? itemURL.resourceValues(forKeys: [.tagNamesKey]).tagNames {
            let tags = tagNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { Tag(name: $0, colorCode: 0) }
            return tags.isEmpty ? nil : tags
        }
        return nil
    }

    nonisolated private static func entrySupplementaryMetadata(
        url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient,
    ) -> EntrySupplementaryMetadata? {
        if isDirectory {
            if entryLoadingClient.isPackageDirectory(url) {
                return nil
            }
            let ext = url.pathExtension.lowercased()
            if ext == CollectionConstants.fileExtension {
                return nil
            }
            guard let itemCount = entryLoadingClient.getFolderItemCount(url) else {
                return nil
            }
            return .folderItemCount(itemCount)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext),
           let resolution = entryLoadingClient.getImageResolution(url)
        {
            return .imageResolution(width: resolution.width, height: resolution.height)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext),
           let fileSizeInBytes = entryLoadingClient.getFileSizeInBytes(url)
        {
            return .compressedFileSize(fileSizeInBytes)
        }

        return nil
    }
}

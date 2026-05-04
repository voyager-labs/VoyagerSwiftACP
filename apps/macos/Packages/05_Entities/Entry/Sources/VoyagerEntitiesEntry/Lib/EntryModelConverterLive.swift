import Foundation
import VoyagerEntitiesTag
import VoyagerShared

public enum EntryModelConverterLive {
    public nonisolated static func convertURLToEntry(
        _ itemURL: URL,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient
    ) -> EntryModel? {
        var isDirectory: ObjCBool = false
        guard entryLoadingClient.fileExistsAtPath(itemURL.path, &isDirectory) else {
            return nil
        }

        let resourceValues = try? itemURL.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
            .isHiddenKey,
        ])

        let name = resourceValues?.name ?? itemURL.lastPathComponent
        let size = Int64(resourceValues?.fileSize ?? 0)
        let modifiedDate = resourceValues?.contentModificationDate ?? Date()
        let createdDate = resourceValues?.creationDate ?? Date()
        let addedDate = resourceValues?.addedToDirectoryDate ?? Date()

        let isHidden = resourceValues?.isHidden ?? false || name.hasPrefix(".")

        let metadata = entryLoadingClient.getItemMetadata(itemURL, isDirectory.boolValue, workspaceClient)
        let lastOpenedDate = metadata.lastUsedDate
        let tags = entryTags(from: itemURL)

        let supplementaryMetadata = entrySupplementaryMetadata(
            url: itemURL,
            isDirectory: isDirectory.boolValue,
            entryLoadingClient: entryLoadingClient
        )

        return EntryModel(
            name: name,
            fullPath: itemURL.path,
            isFolder: isDirectory.boolValue,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            fileExtension: itemURL.pathExtension,
            facets: EntryFacets(
                createdDate: createdDate,
                addedDate: addedDate,
                lastOpenedDate: lastOpenedDate,
                kind: metadata.kind,
                creatorApplication: metadata.creatorApplication,
                tags: tags,
                supplementaryMetadata: supplementaryMetadata
            )
        )
    }

    private nonisolated static func entryTags(from itemURL: URL) -> [Tag]? {
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

    private nonisolated static func entrySupplementaryMetadata(
        url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient
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

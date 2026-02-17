import Foundation

enum EntryModelConverterLive {
    private nonisolated static let entryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private nonisolated(unsafe) static let entryByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    nonisolated static func convertURLToEntry(
        _ itemURL: URL,
        entryLoadingClient: EntryLoadingClient,
        workspaceClient: WorkspaceClient,
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

        let additionalInfo = entryAdditionalInfo(
            url: itemURL,
            isDirectory: isDirectory.boolValue,
            entryLoadingClient: entryLoadingClient,
        )

        let formattedSize = isDirectory.boolValue ? "--" : entryByteFormatter.string(fromByteCount: size)
        let formattedModifiedDate = entryDateFormatter.string(from: modifiedDate)
        let formattedCreatedDate = entryDateFormatter.string(from: createdDate)

        return EntryModel(
            name: name,
            fullPath: itemURL.path,
            isDirectory: isDirectory.boolValue,
            isHidden: isHidden,
            size: size,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            addedDate: addedDate,
            lastOpenedDate: lastOpenedDate,
            fileExtension: itemURL.pathExtension,
            kind: metadata.kind,
            creatorApplication: metadata.creatorApplication,
            tags: tags,
            additionalInfo: additionalInfo,
            formattedSize: formattedSize,
            formattedModifiedDate: formattedModifiedDate,
            formattedCreatedDate: formattedCreatedDate,
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

    private nonisolated static func entryAdditionalInfo(
        url: URL,
        isDirectory: Bool,
        entryLoadingClient: EntryLoadingClient,
    ) -> String? {
        if isDirectory {
            if entryLoadingClient.isPackageDirectory(url) {
                return nil
            }
            let ext = url.pathExtension.lowercased()
            if ext == CollectionConstants.fileExtension {
                return nil
            }
            return entryLoadingClient.getFolderItemCount(url)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext) {
            return entryLoadingClient.getImageResolution(url)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext) {
            return entryLoadingClient.getFormattedFileSize(url)
        }

        return nil
    }
}

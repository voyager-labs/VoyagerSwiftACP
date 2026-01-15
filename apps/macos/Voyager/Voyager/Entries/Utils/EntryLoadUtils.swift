import AppKit
import Foundation
import UniformTypeIdentifiers

enum EntryLoadUtils {
    private nonisolated(unsafe) static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    nonisolated static func convertURLToEntry(
        _ itemURL: URL,
        entryClient: EntryClient,
        workspaceClient: WorkspaceClient,
    ) -> Entry? {
        var isDirectory: ObjCBool = false
        guard entryClient.fileExistsAtPath(itemURL.path, &isDirectory) else {
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

        let metadata = entryClient.getItemMetadata(itemURL, isDirectory.boolValue, workspaceClient)
        let lastOpenedDate = metadata.lastUsedDate
        let tags = getTags(from: itemURL)

        let additionalInfo = calculateAdditionalInfo(
            url: itemURL,
            isDirectory: isDirectory.boolValue,
            entryClient: entryClient,
        )

        let formattedSize = isDirectory.boolValue ? "--" : byteFormatter.string(fromByteCount: size)
        let formattedModifiedDate = dateFormatter.string(from: modifiedDate)
        let formattedCreatedDate = dateFormatter.string(from: createdDate)

        return Entry(
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

    private nonisolated static func getTags(from itemURL: URL) -> [FileTag]? {
        if let tagNames = try? itemURL.resourceValues(forKeys: [.tagNamesKey]).tagNames {
            let nameToColorCode = EntryTagUtils.getTagNameToColorCodeMapping()
            return tagNames.map { tagString in
                let colorCode = nameToColorCode[tagString] ?? 0
                return FileTag(name: tagString, colorCode: colorCode)
            }
        }
        return nil
    }

    private nonisolated static func calculateAdditionalInfo(
        url: URL,
        isDirectory: Bool,
        entryClient: EntryClient,
    ) -> String? {
        if isDirectory {
            if entryClient.isPackageDirectory(url) {
                return nil
            }
            let ext = url.pathExtension.lowercased()
            if ext == "voycoll" {
                return nil
            }
            return entryClient.getFolderItemCount(url)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext) {
            return entryClient.getImageResolution(url)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext) {
            return entryClient.getFormattedFileSize(url)
        }

        return nil
    }
}

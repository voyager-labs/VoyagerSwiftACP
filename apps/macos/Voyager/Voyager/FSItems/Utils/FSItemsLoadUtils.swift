import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

enum FSItemsLoadUtils {
    private struct ItemMetadata {
        let kind: String
        let creatorApplication: String?
        let tags: [FileTag]?
        let lastUsedDate: Date?
    }

    nonisolated static func convertURLToFSItem(_ itemURL: URL) -> FSItem? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        let resourceValues = try? itemURL.resourceValues(forKeys: [
            .nameKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
            .contentAccessDateKey,
        ])

        let name = resourceValues?.name ?? itemURL.lastPathComponent
        let size = Int64(resourceValues?.fileSize ?? 0)
        let modifiedDate = resourceValues?.contentModificationDate ?? Date()
        let createdDate = resourceValues?.creationDate ?? Date()
        let addedDate = resourceValues?.addedToDirectoryDate ?? Date()

        let metadata = getItemMetadata(from: itemURL, isDirectory: isDirectory.boolValue)
        let lastOpenedDate = metadata.lastUsedDate

        let additionalInfo = calculateAdditionalInfo(url: itemURL, isDirectory: isDirectory.boolValue)

        return FSItem(
            name: name,
            fullPath: itemURL.path,
            isDirectory: isDirectory.boolValue,
            isHidden: false,
            size: size,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            addedDate: addedDate,
            lastOpenedDate: lastOpenedDate,
            fileExtension: itemURL.pathExtension,
            kind: metadata.kind,
            creatorApplication: metadata.creatorApplication,
            tags: metadata.tags,
            additionalInfo: additionalInfo
        )
    }

    private nonisolated static func getItemMetadata(
        from itemURL: URL,
        isDirectory: Bool
    ) -> ItemMetadata {
        var kind: String
        var creatorApplication: String?
        var tags: [FileTag]?
        var lastUsedDate: Date?

        if isDirectory {
            kind = "Folder"
        } else {
            kind = itemURL.pathExtension.isEmpty ? "File" : itemURL.pathExtension.uppercased() + " File"
        }

        if let mdItem = MDItemCreate(kCFAllocatorDefault, itemURL.path as CFString) {
            if !isDirectory {
                if let contentType = MDItemCopyAttribute(mdItem, kMDItemContentType) as? String {
                    if let uti = UTType(mimeType: contentType) {
                        kind = uti.localizedDescription ?? contentType
                    }
                }

                if let appURL = NSWorkspace.shared.urlForApplication(toOpen: itemURL) {
                    creatorApplication = appURL.deletingPathExtension().lastPathComponent
                }
            }

            if let rawTags = MDItemCopyAttribute(mdItem, "kMDItemUserTags" as CFString) as? [String] {
                let nameToColorCode = FSItemTagUtils.getTagNameToColorCodeMapping()
                tags = rawTags.map { tagString in
                    let colorCode = nameToColorCode[tagString] ?? 0
                    return FileTag(name: tagString, colorCode: colorCode)
                }
            }
            if let lastUsed = MDItemCopyAttribute(mdItem, "kMDItemLastUsedDate" as CFString) as? Date {
                lastUsedDate = lastUsed
            }
        }

        return ItemMetadata(kind: kind, creatorApplication: creatorApplication, tags: tags, lastUsedDate: lastUsedDate)
    }

    private nonisolated static func calculateAdditionalInfo(url: URL, isDirectory: Bool) -> String? {
        if isDirectory {
            return getFolderItemCount(url)
        }

        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "tiff"].contains(ext) {
            return getImageResolution(url)
        }

        if ["zip", "tar", "gz", "bz2", "xz", "rar", "7z", "dmg", "pkg"].contains(ext) {
            return getFormattedFileSize(url)
        }

        return nil
    }

    private nonisolated static func getFolderItemCount(_ url: URL) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let count = contents.count
        if count == 0 {
            return "No items"
        }
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private nonisolated static func getImageResolution(_ url: URL) -> String? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }

        return "\(width) × \(height)"
    }

    private nonisolated static func getFormattedFileSize(_ url: URL) -> String? {
        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize
        else {
            return nil
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true

        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

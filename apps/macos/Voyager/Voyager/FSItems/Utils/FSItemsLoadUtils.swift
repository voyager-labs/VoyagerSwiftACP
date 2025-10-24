import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

enum FSItemsLoadUtils {
    private struct ItemMetadata {
        let kind: String
        let creatorApplication: String?
        let tags: [String]?
        let lastUsedDate: Date?
    }

    nonisolated static func loadItems(at directoryURL: URL, showHidden: Bool = false) -> [FSItem] {
        let fileManager = FileManager.default

        do {
            let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: options
            )
            return contents.compactMap { convertURLToFSItem($0) }
        } catch {
            return []
        }
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
            tags: metadata.tags
        )
    }

    private nonisolated static func getItemMetadata(
        from itemURL: URL,
        isDirectory: Bool
    ) -> ItemMetadata {
        var kind: String
        var creatorApplication: String?
        var tags: [String]?
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
                tags = rawTags.map { tag in
                    if let newlineIndex = tag.firstIndex(of: "\n") {
                        return String(tag[..<newlineIndex])
                    }
                    return tag
                }
            }
            if let lastUsed = MDItemCopyAttribute(mdItem, "kMDItemLastUsedDate" as CFString) as? Date {
                lastUsedDate = lastUsed
            }
        }

        return ItemMetadata(kind: kind, creatorApplication: creatorApplication, tags: tags, lastUsedDate: lastUsedDate)
    }
}

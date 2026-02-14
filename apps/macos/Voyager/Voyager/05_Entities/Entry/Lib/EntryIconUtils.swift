import AppKit
import Foundation
import UniformTypeIdentifiers

enum EntryIconUtils {
    private static let iconCache = NSCache<NSString, NSImage>()
    // TODO: Collection Constants로 이동
    static let voycollIconName = "voycollFileIcon"

    static func icon(for entry: Entry, thumbnail: NSImage?, workspaceClient: WorkspaceClient) -> NSImage {
        if let thumbnail {
            return thumbnail
        }

        let cacheKey = iconCacheKey(for: entry)
        if let cached = getCachedIcon(for: cacheKey) {
            return cached
        }

        let icon: NSImage = if entry.fullPath == "/" {
            workspaceClient.iconForFile("/")
        } else if entry.fileExtension.lowercased() == "voycoll" {
            NSImage(named: voycollIconName)
                ?? workspaceClient.iconForType(.data)
        } else if entry.isDirectory {
            workspaceClient.iconForFile(entry.fullPath)
        } else if let utType = UTType(filenameExtension: entry.fileExtension) {
            workspaceClient.iconForType(utType)
        } else {
            workspaceClient.iconForType(.data)
        }

        if icon.size != .zero {
            setCachedIcon(icon, for: cacheKey)
        }
        return icon
    }

    private static func iconCacheKey(for entry: Entry) -> String {
        if entry.fullPath == "/" {
            return "root:/"
        }
        if entry.fileExtension.lowercased() == "voycoll" {
            return "asset:\(voycollIconName)"
        }
        if entry.isDirectory {
            return "dir:\(entry.fullPath)"
        }
        if let utType = UTType(filenameExtension: entry.fileExtension) {
            return "type:\(utType.identifier)"
        }
        return "generic:file"
    }

    static func getCachedIcon(for key: String) -> NSImage? {
        iconCache.object(forKey: key as NSString)
    }

    static func setCachedIcon(_ icon: NSImage, for key: String) {
        iconCache.setObject(icon, forKey: key as NSString)
    }

    static func clearCache() {
        iconCache.removeAllObjects()
    }
}

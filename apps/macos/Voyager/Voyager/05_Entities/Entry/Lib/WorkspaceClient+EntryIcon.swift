import AppKit
import Foundation
import UniformTypeIdentifiers

private enum EntryIconCache {
    static let cache = NSCache<NSString, NSImage>()
}

extension WorkspaceClient {
    func entryIcon(for entry: EntryModel, thumbnail: NSImage?) -> NSImage {
        if let thumbnail {
            return thumbnail
        }

        let cacheKey = entryIconCacheKey(for: entry)
        if let cached = EntryIconCache.cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let icon: NSImage = if entry.fullPath == "/" {
            iconForFile("/")
        } else if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            NSImage(named: CollectionConstants.fileIconName)
                ?? iconForType(.data)
        } else if entry.isDirectory {
            iconForFile(entry.fullPath)
        } else if let utType = UTType(filenameExtension: entry.fileExtension) {
            iconForType(utType)
        } else {
            iconForType(.data)
        }

        if icon.size != .zero {
            EntryIconCache.cache.setObject(icon, forKey: cacheKey as NSString)
        }
        return icon
    }

    private func entryIconCacheKey(for entry: EntryModel) -> String {
        if entry.fullPath == "/" {
            return "root:/"
        }
        if entry.fileExtension.lowercased() == CollectionConstants.fileExtension {
            return "asset:\(CollectionConstants.fileIconName)"
        }
        if entry.isDirectory {
            return "dir:\(entry.fullPath)"
        }
        if let utType = UTType(filenameExtension: entry.fileExtension) {
            return "type:\(utType.identifier)"
        }
        return "generic:file"
    }

    static func clearEntryIconCache() {
        EntryIconCache.cache.removeAllObjects()
    }
}

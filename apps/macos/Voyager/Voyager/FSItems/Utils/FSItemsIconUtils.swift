import AppKit
import Foundation
import UniformTypeIdentifiers

enum FSItemsIconUtils {
    private static var iconCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func icon(for item: FSItem) -> NSImage {
        let cacheKey = item.isDirectory
            ? "generic:folder"
            : UTType(filenameExtension: item.fileExtension)
            .map { "type:\($0.identifier)" }
            ?? "generic:file"

        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = iconCache[cacheKey] {
            return cached
        }

        let icon: NSImage
        if item.isDirectory {
            icon = NSWorkspace.shared.icon(for: .folder)
        } else if let utType = UTType(filenameExtension: item.fileExtension) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }

        if iconCache.count > 1000 {
            let keysToRemove = Array(iconCache.keys.prefix(500))
            for key in keysToRemove {
                iconCache.removeValue(forKey: key)
            }
        }
        iconCache[cacheKey] = icon

        return icon
    }

    static func clearCache() {
        cacheLock.lock()
        iconCache.removeAll()
        cacheLock.unlock()
    }
}

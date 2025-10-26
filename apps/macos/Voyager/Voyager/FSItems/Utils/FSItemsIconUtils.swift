import AppKit
import Foundation
import UniformTypeIdentifiers

enum FSItemsIconUtils {
    private static var iconCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func icon(for item: FSItem) -> NSImage {
        let cacheKey = item.isDirectory
            ? "dir:\(item.fullPath)"
            : UTType(filenameExtension: item.fileExtension)
            .map { "type:\($0.identifier)" }
            ?? "file:\(item.fullPath)"

        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = iconCache[cacheKey] {
            return cached
        }

        let icon = item.isDirectory
            ? NSWorkspace.shared.icon(forFile: item.fullPath)
            : (UTType(filenameExtension: item.fileExtension)
                .map { NSWorkspace.shared.icon(for: $0) }
                ?? NSWorkspace.shared.icon(forFile: item.fullPath))

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

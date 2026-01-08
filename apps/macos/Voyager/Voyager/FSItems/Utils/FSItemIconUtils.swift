import AppKit
import Foundation
import UniformTypeIdentifiers

enum FSItemIconUtils {
    private static let iconCache = NSCache<NSString, NSImage>()
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    private static let voycollIconName = "voycollFileIcon"

    static func icon(for item: FSItem) -> NSImage {
        if item.fullPath == "/" {
            return NSWorkspace.shared.icon(forFile: "/")
        }

        if item.fileExtension.lowercased() == "voycoll" {
            let cacheKey = "asset:\(voycollIconName)"
            if let cached = iconCache.object(forKey: cacheKey as NSString) {
                return cached
            }
            if let icon = NSImage(named: voycollIconName) {
                iconCache.setObject(icon, forKey: cacheKey as NSString)
                return icon
            }
        }

        if item.isDirectory {
            let cacheKey = "dir:\(item.fullPath)"
            if let cached = iconCache.object(forKey: cacheKey as NSString) {
                return cached
            }
            let icon = NSWorkspace.shared.icon(forFile: item.fullPath)
            iconCache.setObject(icon, forKey: cacheKey as NSString)
            return icon
        }

        let cacheKey = UTType(filenameExtension: item.fileExtension)
            .map { "type:\($0.identifier)" }
            ?? "generic:file"

        if let cached = iconCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let icon: NSImage = if let utType = UTType(filenameExtension: item.fileExtension) {
            NSWorkspace.shared.icon(for: utType)
        } else {
            NSWorkspace.shared.icon(for: .data)
        }

        iconCache.setObject(icon, forKey: cacheKey as NSString)
        return icon
    }

    static func clearCache() {
        iconCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    static func getThumbnail(for path: String) -> NSImage? {
        thumbnailCache.object(forKey: path as NSString)
    }

    static func saveThumbnail(_ image: NSImage, for path: String) {
        thumbnailCache.setObject(image, forKey: path as NSString)
    }
}

import AppKit
import Foundation
import UniformTypeIdentifiers

enum EntryIconUtils {
    private static let iconCache = NSCache<NSString, NSImage>()
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    static let voycollIconName = "voycollFileIcon"

    static func getCachedIcon(for key: String) -> NSImage? {
        iconCache.object(forKey: key as NSString)
    }

    static func setCachedIcon(_ icon: NSImage, for key: String) {
        iconCache.setObject(icon, forKey: key as NSString)
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

// TODO(sunset VOY-273): Temporary compatibility adapter — app-layer TCA client.
import AppKit
import ComposableArchitecture

struct EntryThumbnailCacheClient: Sendable {
    var getThumbnail: @Sendable (_ path: String) -> NSImage?
    var saveThumbnail: @Sendable (_ image: NSImage, _ path: String) -> Void
    var removeThumbnails: @Sendable (_ paths: [String]) -> Void
    var clearCache: @Sendable () -> Void

    nonisolated init(
        getThumbnail: @escaping @Sendable (_ path: String) -> NSImage?,
        saveThumbnail: @escaping @Sendable (_ image: NSImage, _ path: String) -> Void,
        removeThumbnails: @escaping @Sendable (_ paths: [String]) -> Void,
        clearCache: @escaping @Sendable () -> Void,
    ) {
        self.getThumbnail = getThumbnail
        self.saveThumbnail = saveThumbnail
        self.removeThumbnails = removeThumbnails
        self.clearCache = clearCache
    }

    func getThumbnail(for path: String) -> NSImage? {
        getThumbnail(path)
    }

    func saveThumbnail(_ image: NSImage, for path: String) {
        saveThumbnail(image, path)
    }

    func removeThumbnails(for paths: [String]) {
        removeThumbnails(paths)
    }
}

extension EntryThumbnailCacheClient: DependencyKey {
    private nonisolated(unsafe) static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    nonisolated static var liveValue: EntryThumbnailCacheClient {
        .init(
            getThumbnail: { path in
                thumbnailCache.object(forKey: path as NSString)
            },
            saveThumbnail: { image, path in
                thumbnailCache.setObject(image, forKey: path as NSString)
            },
            removeThumbnails: { paths in
                for path in Set(paths) {
                    thumbnailCache.removeObject(forKey: path as NSString)
                }
            },
            clearCache: {
                thumbnailCache.removeAllObjects()
            },
        )
    }

    nonisolated static var testValue: EntryThumbnailCacheClient {
        .init(
            getThumbnail: { _ in nil },
            saveThumbnail: { _, _ in },
            removeThumbnails: { _ in },
            clearCache: {},
        )
    }

    nonisolated static var previewValue: EntryThumbnailCacheClient { testValue }
}

extension DependencyValues {
    nonisolated var entryThumbnailCacheClient: EntryThumbnailCacheClient {
        get { self[EntryThumbnailCacheClient.self] }
        set { self[EntryThumbnailCacheClient.self] = newValue }
    }
}

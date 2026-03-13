import Foundation

enum CollectionFileUtils {
    nonisolated static func isCollectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == CollectionConstants.fileExtension
    }

    nonisolated static func displayName(_ url: URL, fallback: String) -> String {
        if isCollectionFile(url) {
            return url.deletingPathExtension().lastPathComponent
        }
        return fallback
    }
}

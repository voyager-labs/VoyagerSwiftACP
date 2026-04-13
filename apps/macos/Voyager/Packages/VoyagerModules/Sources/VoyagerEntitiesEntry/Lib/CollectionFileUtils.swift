import Foundation

public enum CollectionFileUtils {
    public nonisolated static func isCollectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == CollectionConstants.fileExtension
    }

    public nonisolated static func displayName(_ url: URL, fallback: String) -> String {
        if isCollectionFile(url) {
            return url.deletingPathExtension().lastPathComponent
        }
        return fallback
    }
}

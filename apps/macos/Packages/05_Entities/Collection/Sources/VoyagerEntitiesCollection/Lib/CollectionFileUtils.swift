import Foundation
import VoyagerShared

public enum CollectionFileUtils {
    nonisolated public static func isCollectionFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == CollectionConstants.fileExtension
    }

    nonisolated public static func displayName(_ url: URL, fallback: String) -> String {
        if isCollectionFile(url) {
            return url.deletingPathExtension().lastPathComponent
        }
        return fallback
    }
}

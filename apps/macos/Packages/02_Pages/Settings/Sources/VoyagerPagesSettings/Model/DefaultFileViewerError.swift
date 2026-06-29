import Foundation

public enum DefaultFileViewerError: Error, Sendable, Equatable {
    case permissionDenied
    case systemError(String)
    case partialWrite(message: String)
}

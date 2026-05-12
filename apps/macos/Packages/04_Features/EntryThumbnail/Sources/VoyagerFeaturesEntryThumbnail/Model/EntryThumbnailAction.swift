import ComposableArchitecture
import Foundation

@CasePathable
public enum EntryThumbnailAction: CasePathable, Sendable {
    case requestThumbnails(paths: [String])
    case thumbnailsReady(paths: [String])
    case thumbnailRequestFailed(paths: [String])
}

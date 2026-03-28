import ComposableArchitecture
import Foundation

@CasePathable
enum EntryThumbnailAction: CasePathable, Sendable {
    case requestThumbnails(paths: [String])
    case thumbnailsReady(paths: [String])
    case thumbnailRequestFailed(paths: [String])
}

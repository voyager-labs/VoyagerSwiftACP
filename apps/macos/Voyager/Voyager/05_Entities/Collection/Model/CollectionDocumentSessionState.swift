import Foundation

struct CollectionDocumentSessionState: Equatable, Sendable {
    var isOpening: Bool = false
    var isStale: Bool = false

    var openedURL: URL?
    var openedName: String?
    var originURL: URL?
    var baseline: CollectionBaseline?
}

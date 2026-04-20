import Foundation

struct CollectionDocumentSessionState: Equatable, Sendable {
    enum StaleReason: Equatable, Sendable {
        case invalidatedLocally
        case snapshotHydratedOnOpen
    }

    var isOpening: Bool = false
    var isStale: Bool = false
    var staleReason: StaleReason?
    var lastRefreshAt: Date?
    var didHydrateSnapshotOnOpen: Bool = false
    var isRefreshingHydratedSnapshot: Bool = false
    var isWritingBackRefreshedSnapshot: Bool = false

    var openedURL: URL?
    var openedName: String?
    var originURL: URL?
    var baseline: CollectionBaseline?
}

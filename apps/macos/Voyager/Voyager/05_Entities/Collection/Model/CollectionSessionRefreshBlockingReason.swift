import Foundation

enum CollectionSessionRefreshBlockingReason: Equatable, Sendable {
    case notInCollectionMode
    case notStale
    case dirtyCollection
    case searchInFlight
    case refreshInFlight
    case writeBackInFlight
    case missingOpenedURL
    case missingCollectionContext
    case missingBaseline
}

import Foundation
import VoyagerEntitiesCollection

struct ToolbarCollectionStatusViewState: Equatable {
    let showsUnsavedIndicator: Bool
    let showsStaleIndicator: Bool
    let showsRefreshAffordance: Bool
    let isRefreshEnabled: Bool
    let refreshBlockingReason: CollectionSessionRefreshBlockingReason?

    init(
        isCollectionMode: Bool,
        openedCollectionURLExists: Bool,
        isOpenedCollectionDirty: Bool,
        isOpenedCollectionStale: Bool,
        refreshBlockingReason: CollectionSessionRefreshBlockingReason?,
    ) {
        showsUnsavedIndicator = isCollectionMode && (!openedCollectionURLExists || isOpenedCollectionDirty)
        showsStaleIndicator = isCollectionMode && isOpenedCollectionStale
        showsRefreshAffordance = isCollectionMode && isOpenedCollectionStale && refreshBlockingReason == nil
        isRefreshEnabled = refreshBlockingReason == nil
        self.refreshBlockingReason = refreshBlockingReason
    }
}

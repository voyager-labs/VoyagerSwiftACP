import Foundation

struct ToolbarCollectionStatusViewState: Equatable {
    let showsUnsavedIndicator: Bool
    let showsStaleIndicator: Bool
    let showsRefreshAffordance: Bool
    let isRefreshEnabled: Bool

    init(
        isCollectionMode: Bool,
        openedCollectionURLExists: Bool,
        isOpenedCollectionDirty: Bool,
        isOpenedCollectionStale: Bool,
        canRefreshStaleCollection: Bool,
    ) {
        showsUnsavedIndicator = isCollectionMode && (!openedCollectionURLExists || isOpenedCollectionDirty)
        showsStaleIndicator = isCollectionMode && isOpenedCollectionStale
        showsRefreshAffordance = isCollectionMode && isOpenedCollectionStale
        isRefreshEnabled = canRefreshStaleCollection
    }
}

import Foundation

struct ToolbarCollectionStatusViewState: Equatable {
    let showsUnsavedIndicator: Bool
    let showsStaleIndicator: Bool

    init(
        isCollectionMode: Bool,
        openedCollectionURLExists: Bool,
        isOpenedCollectionDirty: Bool,
        isOpenedCollectionStale: Bool,
    ) {
        showsUnsavedIndicator = isCollectionMode && (!openedCollectionURLExists || isOpenedCollectionDirty)
        showsStaleIndicator = isCollectionMode && isOpenedCollectionStale
    }
}

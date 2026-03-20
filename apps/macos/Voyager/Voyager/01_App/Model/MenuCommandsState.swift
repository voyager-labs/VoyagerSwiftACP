import IdentifiedCollections

struct MenuCommandsState: Equatable {
    var hasFocusedWindow: Bool

    var canOpen: Bool
    var canQuickLook: Bool

    var canGoBack: Bool
    var canGoForward: Bool
    var canGoToEnclosingDirectory: Bool

    var canSaveCollection: Bool

    var sidebarVisible: Bool
    var showHiddenFiles: Bool

    var viewLayout: ContentViewLayout
    var groupKey: GroupKey
    var sortKey: SortKey
    var sortOrder: SortOrder

    var canUndo: Bool
    var canRedo: Bool
    var selectedItemCount: Int
    var isComposerPresented: Bool

    init() {
        hasFocusedWindow = false
        canOpen = false
        canQuickLook = false
        canGoBack = false
        canGoForward = false
        canGoToEnclosingDirectory = false
        canSaveCollection = false
        sidebarVisible = false
        showHiddenFiles = false
        viewLayout = .list
        groupKey = .none
        sortKey = .name
        sortOrder = .ascending
        canUndo = false
        canRedo = false
        selectedItemCount = 0
        isComposerPresented = false
    }

    init(state: AppRootState) {
        self.init()

        guard let focusedID = state.windowManager.focusedWindowID,
              let window = state.windowManager.windows[id: focusedID]
        else {
            return
        }

        let windowState = window.window

        hasFocusedWindow = true
        canOpen = windowState.content.entryViewLayout.entryOperations.hasSelectableEntries
        canQuickLook = windowState.content.entryViewLayout.entryOperations.hasSelectableEntries
        canGoBack = windowState.content.navigation.canGoBack
        canGoForward = windowState.content.navigation.canGoForward
        canGoToEnclosingDirectory = windowState.content.navigation.canGoToEnclosingDirectory
        canSaveCollection = windowState.content.canSaveCollection
        sidebarVisible = windowState.sidebar.sidebarVisible
        showHiddenFiles = windowState.content.entryViewLayout.showHiddenFiles
        viewLayout = windowState.content.viewLayout
        groupKey = windowState.content.entryViewLayout.entryArrangements.groupKey
        sortKey = windowState.content.entryViewLayout.entryArrangements.sortKey
        sortOrder = windowState.content.entryViewLayout.entryArrangements.sortOrder
        canUndo = windowState.content.entryViewLayout.entryOperations.canUndoEntryAction
        canRedo = windowState.content.entryViewLayout.entryOperations.canRedoEntryAction
        selectedItemCount = windowState.content.entryViewLayout.selectedIds.count
        isComposerPresented = windowState.content.composer.isPresented
    }
}

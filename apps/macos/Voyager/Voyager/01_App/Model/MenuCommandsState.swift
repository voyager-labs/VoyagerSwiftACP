import IdentifiedCollections
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared

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

    var viewLayout: EntryViewLayoutState.Mode
    var groupKey: GroupKey
    var sortKey: SortKey
    var sortOrder: VoyagerShared.SortOrder

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
        let selectedIds = windowState.content.entryViewLayout.selectedIds
        canOpen = !selectedIds.isEmpty
        canQuickLook = !selectedIds.isEmpty
        canGoBack = windowState.content.navigation.canGoBack
        canGoForward = windowState.content.navigation.canGoForward
        canGoToEnclosingDirectory = windowState.content.navigation.canGoToEnclosingDirectory
        canSaveCollection = windowState.content.canSaveCollection
        sidebarVisible = windowState.sidebar.sidebarVisible
        showHiddenFiles = windowState.content.entryViewLayout.showHiddenFiles
        viewLayout = windowState.content.entryViewLayout.mode
        groupKey = windowState.content.entryViewLayout.entryArrangements.groupKey
        sortKey = windowState.content.entryViewLayout.entryArrangements.sortKey
        sortOrder = windowState.content.entryViewLayout.entryArrangements.sortOrder
        canUndo = windowState.content.entryViewLayout.entryOperations.canUndoEntryAction
        canRedo = windowState.content.entryViewLayout.entryOperations.canRedoEntryAction
        selectedItemCount = selectedIds.count
        isComposerPresented = windowState.content.composer.isPresented
    }
}

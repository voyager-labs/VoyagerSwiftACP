import IdentifiedCollections
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

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
        let projection = windowState.menuCommandProjection
        canOpen = projection.canOpen
        canQuickLook = projection.canQuickLook
        canGoBack = projection.canGoBack
        canGoForward = projection.canGoForward
        canGoToEnclosingDirectory = projection.canGoToEnclosingDirectory
        canSaveCollection = projection.canSaveCollection
        sidebarVisible = projection.sidebarVisible
        showHiddenFiles = projection.showHiddenFiles
        viewLayout = projection.viewLayout
        groupKey = projection.groupKey
        sortKey = projection.sortKey
        sortOrder = projection.sortOrder
        canUndo = projection.canUndo
        canRedo = projection.canRedo
        selectedItemCount = projection.selectedItemCount
        isComposerPresented = projection.isComposerPresented
    }
}

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

    var canPerformEntryCommands: Bool
    var canOpen: Bool
    var canQuickLook: Bool

    var canGoBack: Bool
    var canGoForward: Bool
    var canGoToEnclosingDirectory: Bool

    var canSaveCollection: Bool
    var isActiveContentTabPinned: Bool
    var canRestoreLastClosedTab: Bool
    var selectedContentTabCount: Int
    var canDuplicateSelectedContentTabs: Bool
    var canDuplicateActiveContentTab: Bool

    var duplicateContentTabTitle: String {
        selectedContentTabCount > 1 ? "Duplicate \(selectedContentTabCount) Tabs" : "Duplicate Tab"
    }

    var canDuplicateEntries: Bool {
        selectedContentTabCount <= 1 && canPerformEntryCommands && selectedItemCount > 0
    }

    var closeTabTitle: String {
        "Close Tab"
    }

    var showsCloseTabCommand: Bool {
        !isActiveContentTabPinned
    }

    var pinTabTitle: String {
        isActiveContentTabPinned ? "Unpin Tab" : "Pin Tab"
    }

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
    var isContextualAiChatPresented: Bool

    init() {
        hasFocusedWindow = false
        canPerformEntryCommands = false
        canOpen = false
        canQuickLook = false
        canGoBack = false
        canGoForward = false
        canGoToEnclosingDirectory = false
        canSaveCollection = false
        isActiveContentTabPinned = false
        canRestoreLastClosedTab = false
        selectedContentTabCount = 0
        canDuplicateSelectedContentTabs = false
        canDuplicateActiveContentTab = false
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
        isContextualAiChatPresented = false
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
        canPerformEntryCommands = projection.canPerformEntryCommands
        canOpen = projection.canOpen
        canQuickLook = projection.canQuickLook
        canGoBack = projection.canGoBack
        canGoForward = projection.canGoForward
        canGoToEnclosingDirectory = projection.canGoToEnclosingDirectory
        canSaveCollection = projection.canSaveCollection
        isActiveContentTabPinned = projection.isActiveContentTabPinned
        canRestoreLastClosedTab = projection.canRestoreLastClosedTab
        selectedContentTabCount = projection.selectedContentTabCount
        canDuplicateSelectedContentTabs = projection.canDuplicateSelectedContentTabs
        canDuplicateActiveContentTab = projection.canDuplicateActiveContentTab
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
        isContextualAiChatPresented = projection.isContextualAiChatPresented
    }
}

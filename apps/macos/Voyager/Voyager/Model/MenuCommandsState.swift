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
    var canOpenNewContentTab: Bool
    var canToggleActiveContentTabPin: Bool
    var isActiveContentTabPinned: Bool
    var canRestoreLastClosedTab: Bool
    var selectedContentTabCount: Int
    var canCloseSelectedContentTabs: Bool
    var canCloseActiveContentTab: Bool
    var canDuplicateSelectedContentTabs: Bool
    var canDuplicateActiveContentTab: Bool

    var duplicateContentTabTitle: String {
        selectedContentTabCount > 1 ? "Duplicate \(selectedContentTabCount) Tabs" : "Duplicate Tab"
    }

    var canDuplicateEntries: Bool {
        selectedContentTabCount <= 1 && canPerformEntryCommands && selectedItemCount > 0
    }

    var closeTabTitle: String {
        selectedContentTabCount > 1 ? "Close \(selectedContentTabCount) Tabs" : "Close Tab"
    }

    var showsCloseTabCommand: Bool {
        selectedContentTabCount > 1 || !isActiveContentTabPinned
    }

    var canCloseTab: Bool {
        selectedContentTabCount > 1 ? canCloseSelectedContentTabs : canCloseActiveContentTab
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
    var isNewChatPresented: Bool
    var isChatHistoryPresented: Bool
    var canUseAiChatInspector: Bool

    var newChatTitle: String {
        isNewChatPresented ? "Close Chat" : "New Chat"
    }

    var chatHistoryTitle: String {
        isChatHistoryPresented ? "Hide Chat History" : "Show Chat History"
    }

    init() {
        hasFocusedWindow = false
        canPerformEntryCommands = false
        canOpen = false
        canQuickLook = false
        canGoBack = false
        canGoForward = false
        canGoToEnclosingDirectory = false
        canSaveCollection = false
        canOpenNewContentTab = false
        canToggleActiveContentTabPin = false
        isActiveContentTabPinned = false
        canRestoreLastClosedTab = false
        selectedContentTabCount = 0
        canCloseSelectedContentTabs = false
        canCloseActiveContentTab = false
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
        isNewChatPresented = false
        isChatHistoryPresented = false
        canUseAiChatInspector = false
    }

    init(state: AppRootState) {
        self.init()

        guard let focusedID = state.windowManager.focusedWindowID,
              !state.windowManager.closingWindowIDs.contains(focusedID),
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
        canOpenNewContentTab = projection.canOpenNewContentTab
        canToggleActiveContentTabPin = projection.canToggleActiveContentTabPin
        isActiveContentTabPinned = projection.isActiveContentTabPinned
        canRestoreLastClosedTab = projection.canRestoreLastClosedTab
        selectedContentTabCount = projection.selectedContentTabCount
        canCloseSelectedContentTabs = projection.canCloseSelectedContentTabs
        canCloseActiveContentTab = projection.canCloseActiveContentTab
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
        isNewChatPresented = projection.isNewChatPresented
        isChatHistoryPresented = projection.isChatHistoryPresented
        canUseAiChatInspector = projection.canUseAiChatInspector
    }
}

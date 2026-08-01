import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

struct MenuCommandItem: Identifiable, Equatable {
    let id: String
    let title: String
    let command: Command

    enum AppCommand: Equatable {
        case newWindow(path: String? = nil)
        case newTab
        case closeTab
        case togglePinTab
        case restoreLastClosedTab

        case newFolder
        case open
        case quickLook

        case saveCollection
        case saveCollectionAs

        case closeFocusedWindow
        case closeAllWindows

        case goBack
        case goForward
        case goToEnclosingDirectory

        case checkForUpdates
        case setAutomaticUpdate(enabled: Bool)
    }

    enum ViewCommand: Equatable {
        case toggleSidebar
        case toggleShowHiddenFiles
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
    }

    enum EditCommand: Equatable {
        case requestUndo
        case requestRedo
        case find
        case toggleComposer
        case newChat
        case showChatHistory

        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll

        case copyAbsolutePaths
        case copyURLs
    }

    enum Command: Equatable {
        case app(AppCommand)
        case view(ViewCommand)
        case edit(EditCommand)
    }
}

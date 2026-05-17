import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

struct MenuCommandItem: Identifiable, Equatable {
    let id: String
    let title: String
    let command: Command

    enum AppCommand: Equatable, Sendable {
        case newWindow(path: String? = nil)
        case newTab(path: String? = nil)

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

    enum ViewCommand: Equatable, Sendable {
        case toggleSidebar
        case toggleShowHiddenFiles
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
    }

    enum EditCommand: Equatable, Sendable {
        case requestUndo
        case requestRedo
        case toggleComposer

        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll

        case copyAbsolutePaths
        case copyURLs
    }

    enum Command: Equatable, Sendable {
        case app(AppCommand)
        case view(ViewCommand)
        case edit(EditCommand)
    }
}

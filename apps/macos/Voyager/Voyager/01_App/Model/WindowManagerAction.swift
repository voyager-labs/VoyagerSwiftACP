import ComposableArchitecture
import VoyagerEntitiesAi
import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@CasePathable
enum WindowManagerAction: CasePathable, Sendable {
    case delegate(Delegate)
    case lifecycle(Lifecycle)
    case file(FileCommand)
    case window(WindowCommand)
    case view(ViewCommand)
    case edit(EditCommand)
    case event(WindowEvent)
    case windows(IdentifiedActionOf<WindowSessionFeature>)

    @CasePathable
    enum Delegate: Sendable {
        case openAISettings
    }

    @CasePathable
    enum Lifecycle: CasePathable, Sendable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
        case applyAppPreferences(AppPreferencesState)
        case aiConnectionsFileUpdated(AIConnectionsFile)
    }

    @CasePathable
    enum FileCommand: CasePathable, Sendable {
        case newWindow(path: String? = nil)
        case newTab(path: String? = nil)
        case newFolder
        case open
        case quickLook
        case saveCollection
        case saveCollectionAs
    }

    @CasePathable
    enum WindowCommand: CasePathable, Sendable {
        case closeFocusedWindow
        case closeAllWindows
        case goBack
        case goForward
        case goToEnclosingDirectory
        case toggleSidebar
        case toggleShowHiddenFiles
    }

    @CasePathable
    enum ViewCommand: CasePathable, Sendable {
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
    }

    @CasePathable
    enum EditCommand: CasePathable, Sendable {
        case requestUndo
        case requestRedo
        case toggleComposer
        case openContextualAiChat
        case cut
        case copy
        case paste
        case duplicate
        case makeAlias
        case selectAll
        case copyAbsolutePaths
        case copyURLs
    }

    @CasePathable
    enum WindowEvent: CasePathable, Sendable {
        case focusWindow(path: String)
        case windowBecameKey(WindowManagerState.WindowID)
        case windowResignedKey(WindowManagerState.WindowID)
        case windowClosed(WindowManagerState.WindowID)
    }
}

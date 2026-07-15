import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
import VoyagerFeaturesEntryArrangements
import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@CasePathable
enum WindowManagerAction: CasePathable {
    case delegate(Delegate)
    case lifecycle(Lifecycle)
    case file(FileCommand)
    case window(WindowCommand)
    case view(ViewCommand)
    case edit(EditCommand)
    case event(WindowEvent)
    case pinnedContentTabsStoreChanged
    case defaultWindowBootstrapCompleted(requestID: UUID, contentTabs: ContentTabState)
    case defaultWindowBootstrapFailed(requestID: UUID)
    case windows(IdentifiedActionOf<WindowSessionFeature>)

    @CasePathable
    enum Delegate {
        case openAISettings
    }

    @CasePathable
    enum Lifecycle: CasePathable {
        case openInitialWindowIfNeeded
        case reopenWindowIfNeeded(hasVisibleWindows: Bool)
        case applyAppPreferences(AppPreferencesState)
        case aiConnectionsFileUpdated(AIConnectionsFile)
    }

    @CasePathable
    enum FileCommand: CasePathable {
        case newWindow(path: String? = nil, selectEntryID: String? = nil)
        case openCollectionFile(URL)
        case newTab
        case closeTab
        case togglePinTab
        case restoreLastClosedTab
        case newFolder
        case open
        case quickLook
        case saveCollection
        case saveCollectionAs
    }

    @CasePathable
    enum WindowCommand: CasePathable {
        case closeFocusedWindow
        case closeAllWindows
        case goBack
        case goForward
        case goToEnclosingDirectory
        case toggleSidebar
        case toggleShowHiddenFiles
    }

    @CasePathable
    enum ViewCommand: CasePathable {
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
    }

    @CasePathable
    enum EditCommand: CasePathable {
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
    enum WindowEvent: CasePathable {
        case focusWindow(path: String)
        case windowBecameKey(WindowManagerState.WindowID)
        case windowResignedKey(WindowManagerState.WindowID)
        case windowClosed(WindowManagerState.WindowID)
    }
}

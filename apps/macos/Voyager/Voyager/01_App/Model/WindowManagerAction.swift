import ComposableArchitecture

@CasePathable
enum WindowManagerAction: CasePathable, Sendable {
    case openInitialWindowIfNeeded
    case reopenWindowIfNeeded(hasVisibleWindows: Bool)
    case applyAppPreferences(AppPreferencesState)

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
    case toggleSidebar
    case toggleShowHiddenFiles
    case setViewLayout(EntryViewLayoutState.Mode)
    case setGroupKey(GroupKey)
    case setSortKey(SortKey)
    case setSortOrder(SortOrder)
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

    case focusWindow(path: String)
    case windowBecameKey(WindowManagerState.WindowID)
    case windowResignedKey(WindowManagerState.WindowID)
    case windowClosed(WindowManagerState.WindowID)

    case windows(IdentifiedActionOf<WindowSessionFeature>)
}

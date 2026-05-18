import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared

@CasePathable
enum FileManagerWindowAction: CasePathable, Sendable {
    case delegate(Delegate)

    case request(WindowCommand)
    case content(FileManagerContentFeature.Action)
    case sidebar(FileManagerSidebarFeature.Action)
    case inspector(FileManagerInspectorFeature.Action)
    case navigation(ContentPageNavigationFeature.Action)
    case applyAppPreferences(AppPreferencesState)
    case aiConnectionsFileUpdated(AIConnectionsFile)

    case onAppear
    case onDisappear
    case closeWindow

    @CasePathable
    enum WindowCommand: Sendable {
        case newFolder
        case openSelectedItem
        case quickLookSelectedItem
        case saveCollection
        case saveCollectionAs
        case goBack
        case goForward
        case goToEnclosingDirectory
        case toggleSidebar
        case toggleShowHiddenFiles
        case setViewLayout(EntryViewLayoutState.Mode)
        case setGroupKey(GroupKey)
        case setSortKey(SortKey)
        case setSortOrder(VoyagerShared.SortOrder)
        case requestUndo
        case requestRedo
        case toggleComposer
        case openContextualAiChat
        case presentContextualAiChat
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
    enum Delegate: Sendable {
        case openPathInNewWindow(String)
        case openPathInNewTab(String)
        case openAISettings
        case requestAttachmentPicker
    }
}

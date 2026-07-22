import VoyagerFeaturesEntryArrangements
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

public struct FileManagerWindowMenuCommandProjection: Equatable, Sendable {
    public let canPerformEntryCommands: Bool
    public let canOpen: Bool
    public let canQuickLook: Bool
    public let canGoBack: Bool
    public let canGoForward: Bool
    public let canGoToEnclosingDirectory: Bool
    public let canSaveCollection: Bool
    public let isActiveContentTabPinned: Bool
    public let canRestoreLastClosedTab: Bool
    public let sidebarVisible: Bool
    public let showHiddenFiles: Bool
    public let viewLayout: EntryViewLayoutState.Mode
    public let groupKey: GroupKey
    public let sortKey: SortKey
    public let sortOrder: VoyagerShared.SortOrder
    public let canUndo: Bool
    public let canRedo: Bool
    public let selectedItemCount: Int
    public let isComposerPresented: Bool
    public let isContextualAiChatPresented: Bool
    public let canUseAiChatInspector: Bool
}

public extension FileManagerWindowState {
    var menuCommandProjection: FileManagerWindowMenuCommandProjection {
        let selectedIds = content.entryViewLayout.selectedIds
        let activeContentTab = contentTabs.activeTabID.flatMap { contentTabs.tabs[id: $0] }
        let canPerformEntryCommands = !content.isOrdinaryDirectoryLoading

        return FileManagerWindowMenuCommandProjection(
            canPerformEntryCommands: canPerformEntryCommands,
            canOpen: !selectedIds.isEmpty && canPerformEntryCommands,
            canQuickLook: !selectedIds.isEmpty && canPerformEntryCommands,
            canGoBack: content.navigation.canGoBack,
            canGoForward: content.navigation.canGoForward,
            canGoToEnclosingDirectory: content.navigation.canGoToEnclosingDirectory,
            canSaveCollection: content.canSaveCollection,
            isActiveContentTabPinned: activeContentTab?.isPinned == true,
            canRestoreLastClosedTab: ContentTabProjection.restoreCandidate(from: contentTabs) != nil && contentTabs.tabs
                .count < ContentTabConstants.maxTabs && pendingContentTabClose == nil,
            sidebarVisible: sidebar.sidebarVisible,
            showHiddenFiles: content.entryViewLayout.showHiddenFiles,
            viewLayout: content.entryViewLayout.mode,
            groupKey: content.entryViewLayout.entryArrangements.groupKey,
            sortKey: content.entryViewLayout.entryArrangements.sortKey,
            sortOrder: content.entryViewLayout.entryArrangements.sortOrder,
            canUndo: content.entryViewLayout.entryOperations.canUndoEntryAction,
            canRedo: content.entryViewLayout.entryOperations.canRedoEntryAction,
            selectedItemCount: selectedIds.count,
            isComposerPresented: content.composer.isPresented,
            isContextualAiChatPresented: inspector.inspectorVisible
                && inspector.inspectorPaneExists
                && inspector.activeMode == .chat,
            canUseAiChatInspector: contentTabs.activeTabID.map { supportsInspector(tabID: $0) } ?? false,
        )
    }
}

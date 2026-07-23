import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
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
    public let canOpenNewContentTab: Bool
    public let canToggleActiveContentTabPin: Bool
    public let isActiveContentTabPinned: Bool
    public let canRestoreLastClosedTab: Bool
    public let selectedContentTabCount: Int
    public let canCloseSelectedContentTabs: Bool
    public let canCloseActiveContentTab: Bool
    public let canDuplicateSelectedContentTabs: Bool
    public let canDuplicateActiveContentTab: Bool
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
}

public extension FileManagerWindowState {
    var menuCommandProjection: FileManagerWindowMenuCommandProjection {
        let selectedIds = content.entryViewLayout.selectedIds
        let activeContentTab = contentTabs.activeTabID.flatMap { contentTabs.tabs[id: $0] }
        let canPerformEntryCommands = !content.isOrdinaryDirectoryLoading
        let selectedContentTabCount = contentTabs.selectedTabCount
        let canCloseContentTabs = pendingSelectedContentTabClose == nil
            && pendingContentTabClose == nil
            && pendingContentTabTeardown == nil
        let isBatchCloseIdle = pendingSelectedContentTabClose == nil
        let canDuplicateContentTabs = contentTabs.tabs.count < ContentTabConstants.maxTabs
            && isBatchCloseIdle
            && pendingContentTabClose == nil
            && pendingContentTabTeardown == nil

        return FileManagerWindowMenuCommandProjection(
            canPerformEntryCommands: canPerformEntryCommands,
            canOpen: !selectedIds.isEmpty && canPerformEntryCommands,
            canQuickLook: !selectedIds.isEmpty && canPerformEntryCommands,
            canGoBack: content.navigation.canGoBack,
            canGoForward: content.navigation.canGoForward,
            canGoToEnclosingDirectory: content.navigation.canGoToEnclosingDirectory,
            canSaveCollection: content.canSaveCollection,
            canOpenNewContentTab: contentTabs.tabs.count < ContentTabConstants.maxTabs && isBatchCloseIdle,
            canToggleActiveContentTabPin: activeContentTab != nil
                && isBatchCloseIdle
                && pendingContentTabClose == nil,
            isActiveContentTabPinned: activeContentTab?.isPinned == true,
            canRestoreLastClosedTab: ContentTabProjection.restoreCandidate(from: contentTabs) != nil && contentTabs.tabs
                .count < ContentTabConstants.maxTabs && isBatchCloseIdle && pendingContentTabClose == nil,
            selectedContentTabCount: selectedContentTabCount,
            canCloseSelectedContentTabs: selectedContentTabCount > 1 && canStartSelectedContentTabClose,
            canCloseActiveContentTab: selectedContentTabCount <= 1
                && activeContentTab != nil
                && activeContentTab?.isPinned != true
                && canCloseContentTabs,
            canDuplicateSelectedContentTabs: selectedContentTabCount > 1 && canDuplicateContentTabs,
            canDuplicateActiveContentTab: selectedContentTabCount <= 1 && activeContentTab != nil
                && canDuplicateContentTabs,
            sidebarVisible: sidebar.sidebarVisible,
            showHiddenFiles: content.entryViewLayout.showHiddenFiles,
            viewLayout: content.entryViewLayout.mode,
            groupKey: content.entryViewLayout.entryArrangements.groupKey,
            sortKey: content.entryViewLayout.entryArrangements.sortKey,
            sortOrder: content.entryViewLayout.entryArrangements.sortOrder,
            canUndo: validatedUndoRedoTarget(for: .undo) != nil,
            canRedo: validatedUndoRedoTarget(for: .redo) != nil,
            selectedItemCount: selectedIds.count,
            isComposerPresented: content.composer.isPresented,
            isContextualAiChatPresented: inspector.inspectorVisible
                && inspector.inspectorPaneExists
                && inspector.activeMode == .chat,
        )
    }
}

extension FileManagerWindowState {
    func validatedUndoRedoTarget(for direction: EntryActionDirection) -> UndoManagerRecordIdentity? {
        guard undoRedoPhase == .idle,
              pendingSelectedContentTabClose == nil
        else { return nil }

        let managerTarget: UndoManagerRecordIdentity?
        switch direction {
        case .undo:
            guard undoManagerAvailability.canUndo else { return nil }
            managerTarget = undoManagerAvailability.undoTarget
        case .redo:
            guard undoManagerAvailability.canRedo else { return nil }
            managerTarget = undoManagerAvailability.redoTarget
        }
        guard let managerTarget else { return nil }

        var candidates: [EntryOperationsState] = []
        if sidebarEntryDropOperations.undoOwnerID == managerTarget.ownerID {
            candidates.append(sidebarEntryDropOperations)
        }
        if content.entryViewLayout.entryOperations.undoOwnerID == managerTarget.ownerID {
            candidates.append(content.entryViewLayout.entryOperations)
        }
        for (tabID, contentState) in tabContentStates where tabID != contentTabs.activeTabID {
            let operations = contentState.entryViewLayout.entryOperations
            if operations.undoOwnerID == managerTarget.ownerID {
                candidates.append(operations)
            }
        }
        guard candidates.count == 1, let operations = candidates.first else { return nil }

        let localRecord = switch direction {
        case .undo:
            operations.latestUndoRecord
        case .redo:
            operations.latestRedoRecord
        }
        guard let localRecord,
              localRecord.id == managerTarget.recordID,
              !operations.isEntryActionBusy(localRecord)
        else { return nil }
        return managerTarget
    }
}

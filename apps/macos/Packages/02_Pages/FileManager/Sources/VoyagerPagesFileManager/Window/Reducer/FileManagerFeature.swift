import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    @Dependency(\.fileOperationUndoManagerClient)
    var fileOperationUndoManagerClient
    @Dependency(\.contentTabPinnedRecordClient)
    var contentTabPinnedRecordClient
    @Dependency(\.fileManagerPinnedRecordOwner)
    var pinnedRecordPersistenceOwnership
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard state.contentTabMoveParticipantRequestID == nil
                || isContentTabMoveParticipantActionAllowed(action)
            else { return .none }
            return coreBody.reduce(into: &state, action: action)
        }
    }

    func isContentTabMoveParticipantActionAllowed(_ action: Action) -> Bool {
        switch action {
        case .applyCommittedTopNavigationSnapshot,
             .applyExternalCommittedTopNavigationOrder,
             .backgroundAiChat,
             .backgroundAiChatSnapshotPersisted,
             .backgroundInspectorAiChat,
             .backgroundInspectorAiChatSnapshotPersisted,
             .contentTabMoveSucceeded,
             .contentTabMoveRejected,
             .onDisappear:
            true

        case .tabContent(_, .internal(.applyNavigationState)),
             .tabContent(_, .internal(.startObservingSystemNotifications)),
             .tabContent(_, .internal(.stopObservingSystemNotifications)):
            true

        case .internal(.entryActionCompleted):
            true

        case let .content(.entryViewLayout(.entryOperations(entryAction))),
             let .tabContent(_, .entryViewLayout(.entryOperations(entryAction))),
             let .internal(.sidebarEntryDrop(entryAction)):
            isEntryOperationsCompletionActionAllowed(entryAction)

        default:
            false
        }
    }

    func isEntryOperationsCompletionActionAllowed(_ action: EntryOperationsAction) -> Bool {
        switch action {
        case .lifecycle(.operationStarted),
             .lifecycle(.operationFinished),
             .lifecycle(.dropOperationFinished),
             .lifecycle(.entryActionCompleted),
             .lifecycle(.emptyTrashCompleted),
             .lifecycle(.pathsMutated),
             .outcome(.entriesMutated),
             .outcome(.undoManagerAvailabilityChanged),
             .outcome(.entryActionReplayFinished):
            true

        default:
            false
        }
    }
}

extension ContentTabPageAnchor {
    var supportsPinnedRecordPersistence: Bool {
        switch self {
        case .homeDefault, .directory, .collectionFile:
            true
        case .virtualCollection, .aiChat:
            false
        }
    }
}

func fileManagerContentState(
    for tabID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    state.contentTabs.activeTabID == tabID ? state.content : state.tabContentStates[tabID]
}

func isComposerSaveRequest(_ action: FileManagerContentAction) -> Bool {
    switch action {
    case .composer(.view(.saveCollection)),
         .composer(.view(.saveCollectionAs)):
        true
    default:
        false
    }
}

func isPinnedRecordPersistenceTerminal(_ action: ContentTabAction) -> Bool {
    pinnedRecordPersistenceResult(action) != nil
}

func pinnedRecordPersistenceResult(
    _ action: ContentTabAction,
) -> ContentTabPinnedRecordPersistenceResult? {
    switch action {
    case let .pinnedRecordSaveSucceeded(tabID, context):
        .init(tabID: tabID, context: context, terminal: nil)
    case let .pinnedRecordSaveFailed(tabID, context, _):
        .init(tabID: tabID, context: context, terminal: .failed(.save))
    case let .pinnedRecordStoreUnavailable(tabID, context, failure, _):
        .init(
            tabID: tabID,
            context: context,
            terminal: .failed(.storeUnavailable(failure)),
        )
    case let .pinnedRecordSaveNotApplied(tabID, context, reason, _):
        .init(
            tabID: tabID,
            context: context,
            terminal: .failed(reason == .superseded ? .superseded : .cancelled),
        )
    default:
        nil
    }
}

func isSelectionAllowedDuringBatchClose(_ action: ContentTabAction) -> Bool {
    switch action {
    case .delegate,
         .toggleSelection,
         .selectRange,
         .collapseSelectionToActive,
         .pinnedRecordSaveSucceeded,
         .pinnedRecordSaveFailed,
         .pinnedRecordStoreUnavailable,
         .pinnedRecordSaveNotApplied:
        true
    default:
        false
    }
}

func rebasingPinnedRecordRollback(
    _ action: ContentTabAction,
    to rollback: ContentTabPinnedRecordRollbackSnapshot?,
) -> ContentTabAction {
    guard let rollback else { return action }
    return switch action {
    case let .pinnedRecordSaveFailed(tabID, context, _):
        .pinnedRecordSaveFailed(tabID: tabID, context: context, rollback: rollback)
    case let .pinnedRecordStoreUnavailable(tabID, context, failure, _):
        .pinnedRecordStoreUnavailable(
            tabID: tabID,
            context: context,
            failure: failure,
            rollback: rollback,
        )
    case let .pinnedRecordSaveNotApplied(tabID, context, reason, _):
        .pinnedRecordSaveNotApplied(
            tabID: tabID,
            context: context,
            reason: reason,
            rollback: rollback,
        )
    default:
        action
    }
}

func isStalePinnedRecordPersistenceResult(
    _ action: ContentTabAction,
    in state: ContentTabState,
) -> Bool {
    switch action {
    case let .pinnedRecordSaveSucceeded(tabID, context),
         let .pinnedRecordSaveFailed(tabID, context, _),
         let .pinnedRecordStoreUnavailable(tabID, context, _, _),
         let .pinnedRecordSaveNotApplied(tabID, context, _, _):
        !state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID)
    default:
        false
    }
}

func isDirectPinMutation(_ action: ContentTabAction) -> Bool {
    switch action {
    case .pin, .unpin:
        true
    default:
        false
    }
}

func isDirectCloseMutation(_ action: ContentTabAction) -> Bool {
    switch action {
    case .requestClose, .close, .commitClose:
        true
    default:
        false
    }
}

func isSelectedContentTabPinMutationPersistenceReplacement(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
) -> Bool {
    guard case let .updateActivePageAnchor(id, _) = action else { return false }
    return id == tabID
}

func isCorrelatedSelectedContentTabPinMutation(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
    target: SelectedContentTabPinMutationTargetState,
) -> Bool {
    switch action {
    case let .delegate(.persistPinnedRecord(request)):
        request.tabID == tabID
    case let .pin(id, _):
        id == tabID && target == .pinned
    case let .unpin(id, _):
        id == tabID && target == .unpinned
    case let .updateActivePageAnchor(id, _):
        id == tabID
    case let .pinnedRecordSaveSucceeded(id, _),
         let .pinnedRecordSaveFailed(id, _, _),
         let .pinnedRecordStoreUnavailable(id, _, _, _),
         let .pinnedRecordSaveNotApplied(id, _, _, _):
        id == tabID
    default:
        false
    }
}

func isCorrelatedSelectedContentTabCloseMutation(
    _ action: ContentTabAction,
    for tabID: ContentTabID,
) -> Bool {
    switch action {
    case let .delegate(.persistPinnedRecord(request)):
        request.tabID == tabID
    case let .setCurrent(id),
         let .requestClose(id),
         let .close(id),
         let .commitClose(id),
         let .pin(id, _),
         let .pinUsingDormantSlot(id, _),
         let .unpin(id, _):
        id == tabID
    case let .updateActivePageAnchor(id, _):
        id == tabID
    case let .pinnedRecordSaveSucceeded(id, _):
        id == tabID
    case let .pinnedRecordSaveFailed(id, _, _):
        id == tabID
    case let .pinnedRecordStoreUnavailable(id, _, _, _):
        id == tabID
    case let .pinnedRecordSaveNotApplied(id, _, _, _):
        id == tabID
    default:
        false
    }
}

struct ContentTabPinnedRecordPersistenceResult {
    let tabID: ContentTabID
    let context: ContentTabPinnedRecordTerminalContext
    let terminal: FileManagerTopNavigationIntentTerminal?
}

extension FileManagerWindowState {
    func isCurrentSelectedContentTabClose(operationID: UUID, tabID: ContentTabID) -> Bool {
        guard !isClosing,
              let batch = pendingSelectedContentTabClose,
              let pendingClose = pendingContentTabClose
        else { return false }
        return batch.operationID == operationID
            && batch.currentTabID == tabID
            && pendingClose.batchOperationID == operationID
            && pendingClose.tabID == tabID
    }
}

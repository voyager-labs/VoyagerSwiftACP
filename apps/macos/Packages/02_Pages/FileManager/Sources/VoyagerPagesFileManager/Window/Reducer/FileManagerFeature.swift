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
    private var fileOperationUndoManagerClient

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .content(contentAction):
                guard state.pendingSelectedContentTabClose == nil
                    || !contentAction.isComposerSaveRequest
                else { return .none }
                guard let activeTabID = state.contentTabs.activeTabID,
                      state.contentTabs.tabs[id: activeTabID] != nil
                else { return .none }
                let generation = undoManagerGeneration(tabID: activeTabID, state: state)
                let effect = FileManagerContentFeature().reduce(
                    into: &state.content,
                    action: contentAction,
                )
                return effect.map {
                    Self.routeContentEffectAction(
                        $0,
                        tabID: activeTabID,
                        undoManagerGeneration: generation,
                    )
                }

            case let .tabContent(tabID, contentAction):
                guard state.contentTabs.tabs[id: tabID] != nil else { return .none }

                let generation = undoManagerGeneration(tabID: tabID, state: state)
                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: contentAction,
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map {
                    Self.routeContentEffectAction(
                        $0,
                        tabID: tabID,
                        undoManagerGeneration: generation,
                    )
                }

            case let .internal(.entryActionCompleted(tabID, record, expectedGeneration)):
                guard record.operationKind.isUndoable,
                      let expectedGeneration,
                      undoManagerGeneration(tabID: tabID, state: state) == expectedGeneration,
                      state.contentTabs.tabs[id: tabID] != nil,
                      let windowID = state.windowID
                else { return .none }

                let scope = UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
                guard fileOperationUndoManagerClient.registerUndo(scope, expectedGeneration, record) else {
                    clearLogicalUndoHistory(tabID: tabID, state: &state)
                    return .none
                }

                let isActiveTab = state.contentTabs.activeTabID == tabID
                guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
                    return .none
                }
                let effect = FileManagerContentFeature().reduce(
                    into: &contentState,
                    action: .entryViewLayout(.entryOperations(.lifecycle(.entryActionCompleted(record)))),
                )
                if isActiveTab {
                    state.content = contentState
                }
                state.tabContentStates[tabID] = contentState
                return effect.map { .tabContent(tabID: tabID, action: $0) }

            default:
                return .none
            }
        }

        Scope(state: \.content.navigation, action: \.navigation) {
            ContentPageNavigationFeature()
        }

        Scope(state: \.sidebarEntryDropOperations, action: \.internal.sidebarEntryDrop) {
            EntryOperationsFeature()
        }

        Scope(state: \.sidebar, action: \.sidebar) {
            FileManagerSidebarFeature()
        }

        Scope(state: \.inspector, action: \.inspector) {
            FileManagerInspectorFeature()
        }

        Reduce { state, action in
            switch action {
            case let .performBatchCloseContentAction(operationID, tabID, contentAction):
                guard state.isCurrentSelectedContentTabClose(operationID: operationID, tabID: tabID) else {
                    return .none
                }
                return FileManagerContentFeature()
                    .reduce(into: &state.content, action: contentAction)
                    .map {
                        .performBatchCloseContentAction(
                            operationID: operationID,
                            tabID: tabID,
                            action: $0,
                        )
                    }
                    .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            case let .performBatchCloseNavigationAction(operationID, tabID, navigationAction):
                guard state.isCurrentSelectedContentTabClose(operationID: operationID, tabID: tabID) else {
                    return .none
                }
                return ContentPageNavigationFeature()
                    .reduce(into: &state.content.navigation, action: navigationAction)
                    .map {
                        .performBatchCloseNavigationAction(
                            operationID: operationID,
                            tabID: tabID,
                            action: $0,
                        )
                    }
                    .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            case let .contentTabs(.pinnedRecordPersistenceRequested(request)):
                return .send(.delegate(.pinnedRecordPersistenceRequested(
                    FileManagerPinnedRecordPersistenceRequest(request: request, route: .single),
                )))

            case let .contentTabs(contentTabAction):
                if let pending = state.pendingSelectedContentTabPinMutation,
                   let currentTabID = pending.currentTabID,
                   contentTabAction.isSelectedContentTabPinMutationPersistenceReplacement(for: currentTabID)
                {
                    return .send(.performSelectedContentTabPinMutation(
                        operationID: pending.operationID,
                        tabID: currentTabID,
                        action: contentTabAction,
                    ))
                }
                guard state.pendingSelectedContentTabClose == nil
                    || contentTabAction.isSelectionAllowedDuringBatchClose
                else { return .none }
                guard state.pendingSelectedContentTabPinMutation == nil
                    || (!contentTabAction.isDirectPinMutation && !contentTabAction.isDirectCloseMutation)
                else { return .none }
                return reduceContentTabAction(contentTabAction, state: &state)

            case let .performSelectedContentTabPinMutation(
                operationID,
                tabID,
                .pinnedRecordPersistenceRequested(request),
            ):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabPinMutation,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      let rollback = pending.currentItemRollbackSnapshot
                else { return .none }
                let rebasedRequest = ContentTabPinnedRecordPersistenceRequest(
                    mutationID: request.mutationID,
                    tabID: request.tabID,
                    intentID: request.intentID,
                    mutation: request.mutation,
                    rollback: rollback,
                )
                return .send(.delegate(.pinnedRecordPersistenceRequested(
                    FileManagerPinnedRecordPersistenceRequest(
                        request: rebasedRequest,
                        route: .selectedPin(operationID: operationID),
                    ),
                )))

            case let .performSelectedContentTabPinMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabPinMutation,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      !contentTabAction.isStalePinnedRecordPersistenceResult(in: state.contentTabs),
                      contentTabAction.isCorrelatedSelectedContentTabPinMutation(
                          for: tabID,
                          target: pending.target,
                      )
                else { return .none }
                let previousActiveTabID = state.contentTabs.previousActiveTabID
                let childEffect = ContentTabFeature().reduce(
                    into: &state.contentTabs,
                    action: contentTabAction,
                )
                state.contentTabs.previousActiveTabID = previousActiveTabID
                state.syncContentTabSidebarItems()
                return childEffect.map {
                    .performSelectedContentTabPinMutation(
                        operationID: operationID,
                        tabID: tabID,
                        action: $0,
                    )
                }
                .cancellable(id: SelectedContentTabPinMutationOperationCancelID(operationID: operationID))

            case let .performSelectedContentTabCloseMutation(
                operationID,
                tabID,
                .pinnedRecordPersistenceRequested(request),
            ):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID
                else { return .none }
                return .send(.delegate(.pinnedRecordPersistenceRequested(
                    FileManagerPinnedRecordPersistenceRequest(
                        request: request,
                        route: .selectedClose(operationID: operationID),
                    ),
                )))

            case let .performSelectedContentTabCloseMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      !contentTabAction.isStalePinnedRecordPersistenceResult(in: state.contentTabs),
                      contentTabAction.isCorrelatedSelectedContentTabCloseMutation(for: tabID)
                else { return .none }
                let childEffect = ContentTabFeature().reduce(
                    into: &state.contentTabs,
                    action: contentTabAction,
                )
                return childEffect.map {
                    .performSelectedContentTabCloseMutation(
                        operationID: operationID,
                        tabID: tabID,
                        action: $0,
                    )
                }
                .cancellable(id: SelectedContentTabCloseOperationCancelID(operationID: operationID))

            default:
                return .none
            }
        }

        FileManagerWindowAiChatSelectionReducer()

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowUndoRoutingReducer()
        FileManagerWindowCommandRoutingReducer()
    }

    private func clearLogicalUndoHistory(tabID: ContentTabID, state: inout State) {
        let isActiveTab = state.contentTabs.activeTabID == tabID
        guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else { return }
        contentState.entryViewLayout.entryOperations.undoRecords.removeAll()
        contentState.entryViewLayout.entryOperations.redoRecords.removeAll()
        if isActiveTab {
            state.content = contentState
        }
        state.tabContentStates[tabID] = contentState
    }

    private func undoManagerGeneration(
        tabID: ContentTabID,
        state: State,
    ) -> FileOperationUndoManagerClient.Generation? {
        guard let windowID = state.windowID else { return nil }
        return fileOperationUndoManagerClient.generation(UndoManagerScope(
            windowID: windowID,
            contentTabID: tabID.rawValue,
        ))
    }

    private static func completedEntryActionRecord(
        from action: FileManagerContentAction,
    ) -> EntryActionRecord? {
        guard case let .entryViewLayout(
            .entryOperations(.lifecycle(.entryActionCompleted(record))),
        ) = action else { return nil }
        return record
    }

    private static func routeContentEffectAction(
        _ action: FileManagerContentAction,
        tabID: ContentTabID,
        undoManagerGeneration: FileOperationUndoManagerClient.Generation?,
    ) -> Action {
        guard let record = completedEntryActionRecord(from: action) else {
            return .tabContent(tabID: tabID, action: action)
        }
        return .internal(.entryActionCompleted(
            tabID: tabID,
            record: record,
            undoManagerGeneration: undoManagerGeneration,
        ))
    }

    private func reduceContentTabAction(
        _ action: ContentTabAction,
        state: inout State,
    ) -> Effect<Action> {
        let preReductionEffect: Effect<Action> = switch action {
        case let .duplicate(sourceID, duplicateID):
            .send(.internal(.duplicateContentTabReduced(
                sourceID: sourceID,
                duplicateID: duplicateID,
                duplicateIDWasPreexisting: state.contentTabs.tabs[id: duplicateID] != nil,
            )))

        case let .duplicateSelected(requests):
            .send(.internal(.duplicateSelectedContentTabsReduced(
                requests: requests,
                preexistingTabIDs: Set(state.contentTabs.tabs.ids),
            )))

        default:
            .none
        }
        let childEffect = ContentTabFeature().reduce(
            into: &state.contentTabs,
            action: action,
        )
        .map { Action.contentTabs($0) }
        return .merge(preReductionEffect, childEffect)
    }
}

func fileManagerContentState(
    for tabID: ContentTabID,
    state: FileManagerWindowState,
) -> FileManagerContentFeature.State? {
    state.contentTabs.activeTabID == tabID ? state.content : state.tabContentStates[tabID]
}

private extension FileManagerContentAction {
    var isComposerSaveRequest: Bool {
        switch self {
        case .composer(.view(.saveCollection)),
             .composer(.view(.saveCollectionAs)):
            true
        default:
            false
        }
    }
}

extension ContentTabAction {
    var isSelectionAllowedDuringBatchClose: Bool {
        switch self {
        case .toggleSelection,
             .selectRange,
             .collapseSelectionToActive,
             .pinnedRecordSaveSucceeded,
             .pinnedRecordSaveFailed,
             .pinnedRecordSaveNotApplied,
             .pinnedRecordPersistenceRequested:
            true
        default:
            false
        }
    }

    func isStalePinnedRecordPersistenceResult(in state: ContentTabState) -> Bool {
        switch self {
        case let .pinnedRecordSaveSucceeded(tabID, context),
             let .pinnedRecordSaveFailed(tabID, context, _),
             let .pinnedRecordSaveNotApplied(tabID, context, _, _):
            !state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: context.intentID)
        default:
            false
        }
    }

    var isDirectPinMutation: Bool {
        switch self {
        case .pin, .unpin:
            true
        default:
            false
        }
    }

    var isDirectCloseMutation: Bool {
        switch self {
        case .requestClose, .close, .commitClose:
            true
        default:
            false
        }
    }

    func isSelectedContentTabPinMutationPersistenceReplacement(for tabID: ContentTabID) -> Bool {
        guard case let .updateActivePageAnchor(id, _) = self else { return false }
        return id == tabID
    }

    func isCorrelatedSelectedContentTabPinMutation(
        for tabID: ContentTabID,
        target: SelectedContentTabPinMutationTargetState,
    ) -> Bool {
        switch self {
        case let .pin(id):
            id == tabID && target == .pinned
        case let .unpin(id):
            id == tabID && target == .unpinned
        case let .updateActivePageAnchor(id, _):
            id == tabID
        case let .pinnedRecordPersistenceRequested(request):
            request.tabID == tabID
        case let .pinnedRecordSaveSucceeded(id, _),
             let .pinnedRecordSaveFailed(id, _, _),
             let .pinnedRecordSaveNotApplied(id, _, _, _):
            id == tabID
        default:
            false
        }
    }

    func isCorrelatedSelectedContentTabCloseMutation(for tabID: ContentTabID) -> Bool {
        switch self {
        case let .setCurrent(id),
             let .requestClose(id),
             let .close(id),
             let .commitClose(id),
             let .pin(id),
             let .unpin(id):
            id == tabID
        case let .updateActivePageAnchor(id, _):
            id == tabID
        case let .pinnedRecordPersistenceRequested(request):
            request.tabID == tabID
        case let .pinnedRecordSaveSucceeded(id, _):
            id == tabID
        case let .pinnedRecordSaveFailed(id, _, _):
            id == tabID
        case let .pinnedRecordSaveNotApplied(id, _, _, _):
            id == tabID
        default:
            false
        }
    }
}

private extension FileManagerWindowState {
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

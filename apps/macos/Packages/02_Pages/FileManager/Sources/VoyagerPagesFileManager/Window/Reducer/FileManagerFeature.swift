import ComposableArchitecture
import Foundation
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations

@Reducer
public struct FileManagerFeature {
    public typealias State = FileManagerWindowState
    public typealias Action = FileManagerWindowAction

    public init() {}

    public var body: some Reducer<State, Action> {
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
            case let .content(contentAction):
                guard state.pendingSelectedContentTabClose == nil
                    || !contentAction.isComposerSaveRequest
                else { return .none }
                return FileManagerContentFeature()
                    .reduce(into: &state.content, action: contentAction)
                    .map(Action.content)

            case let .navigation(navigationAction):
                return ContentPageNavigationFeature()
                    .reduce(into: &state.content.navigation, action: navigationAction)
                    .map(Action.navigation)

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

            case let .contentTabs(contentTabAction):
                guard state.pendingSelectedContentTabClose == nil
                    || contentTabAction.isSelectionAllowedDuringBatchClose
                else { return .none }
                return reduceContentTabAction(contentTabAction, state: &state)

            case let .performSelectedContentTabCloseMutation(operationID, tabID, contentTabAction):
                guard !state.isClosing,
                      let pending = state.pendingSelectedContentTabClose,
                      pending.operationID == operationID,
                      pending.currentTabID == tabID,
                      !contentTabAction.isStalePinnedRecordPersistenceResult(in: state.contentTabs)
                      || contentTabAction.isPinnedRecordSaveNotApplied,
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

        FileManagerWindowNavigationReducer()
        FileManagerWindowLifecycleReducer()
        FileManagerWindowPreferencesReducer()
        FileManagerWindowRoutingReducer()
        FileManagerWindowCommandRoutingReducer()
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
             .pinnedRecordSaveNotApplied:
            true
        default:
            false
        }
    }

    func isStalePinnedRecordPersistenceResult(in state: ContentTabState) -> Bool {
        switch self {
        case let .pinnedRecordSaveSucceeded(tabID, intentID),
             let .pinnedRecordSaveFailed(tabID, intentID, _, _, _),
             let .pinnedRecordSaveNotApplied(tabID, intentID, _, _):
            !state.isCurrentPinnedRecordPersistenceIntent(tabID: tabID, intentID: intentID)
        default:
            false
        }
    }

    var isPinnedRecordSaveNotApplied: Bool {
        if case .pinnedRecordSaveNotApplied = self { return true }
        return false
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
        case let .pinnedRecordSaveSucceeded(id, _):
            id == tabID
        case let .pinnedRecordSaveFailed(id, _, _, _, _):
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

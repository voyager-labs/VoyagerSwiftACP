import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations

@Reducer
struct FileManagerWindowUndoRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.fileOperationUndoManagerClient)
    private var fileOperationUndoManagerClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.undoRedo(.requestUndo))),
            ):
                performUndoRedo(tabID: tabID, direction: .undo, state: &state)

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.undoRedo(.requestRedo))),
            ):
                performUndoRedo(tabID: tabID, direction: .redo, state: &state)

            default:
                .none
            }
        }
    }

    private func undoManagerScope(tabID: ContentTabID, state: State) -> UndoManagerScope? {
        guard let windowID = state.windowID else { return nil }
        return UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
    }

    private func performUndoRedo(
        tabID: ContentTabID,
        direction: FileOperationUndoDirection,
        state: inout State,
    ) -> Effect<Action> {
        guard state.contentTabs.tabs[id: tabID] != nil,
              let scope = undoManagerScope(tabID: tabID, state: state),
              let generation = fileOperationUndoManagerClient.generation(scope)
        else { return .none }

        let isActiveTab = state.contentTabs.activeTabID == tabID
        guard var contentState = isActiveTab ? state.content : state.tabContentStates[tabID] else {
            return .none
        }
        let operations = contentState.entryViewLayout.entryOperations
        let record: EntryActionRecord? = switch direction {
        case .undo:
            operations.canUndoEntryAction ? operations.latestUndoRecord : nil
        case .redo:
            operations.canRedoEntryAction ? operations.latestRedoRecord : nil
        }
        guard let record else { return .none }

        let outcome = fileOperationUndoManagerClient.performUndoRedo(
            scope,
            generation,
            direction,
            record.id,
        )
        switch outcome {
        case .applied:
            let undoRedoAction: EntryOperationsAction.UndoRedo = switch direction {
            case .undo:
                .undoEntryAction(record)
            case .redo:
                .redoEntryAction(record)
            }
            let effect = FileManagerContentFeature().reduce(
                into: &contentState,
                action: .entryViewLayout(.entryOperations(.undoRedo(undoRedoAction))),
            )
            updateContentState(contentState, tabID: tabID, isActiveTab: isActiveTab, state: &state)
            return effect.map { .tabContent(tabID: tabID, action: $0) }

        case .invalidated:
            contentState.entryViewLayout.entryOperations.undoRecords.removeAll()
            contentState.entryViewLayout.entryOperations.redoRecords.removeAll()
            updateContentState(contentState, tabID: tabID, isActiveTab: isActiveTab, state: &state)
            return .none

        case .rejected:
            return .none
        }
    }

    private func updateContentState(
        _ contentState: FileManagerContentState,
        tabID: ContentTabID,
        isActiveTab: Bool,
        state: inout State,
    ) {
        if isActiveTab {
            state.content = contentState
        }
        state.tabContentStates[tabID] = contentState
    }
}

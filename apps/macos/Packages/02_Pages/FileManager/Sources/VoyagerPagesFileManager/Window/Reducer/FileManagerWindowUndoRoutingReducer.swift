import ComposableArchitecture
import Foundation
import VoyagerFeaturesEntryOperations

struct FileOperationUndoRegistrationCancelID: Hashable {
    let scope: UndoManagerScope
}

private enum FileOperationNativeUndoEvent {
    case undo(EntryActionRecord)
    case redo(EntryActionRecord)
}

@Reducer
struct FileManagerWindowUndoRoutingReducer {
    typealias State = FileManagerWindowState
    typealias Action = FileManagerWindowAction

    @Dependency(\.fileOperationUndoManagerClient)
    private var fileOperationUndoManagerClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .internal(.entryActionCompleted(tabID, record, generation)):
                registerNativeUndoEffect(
                    tabID: tabID,
                    record: record,
                    generation: generation,
                    state: state,
                )

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.undoRedo(.requestUndo))),
            ):
                requestNativeUndoRedoEffect(tabID: tabID, isUndo: true, state: state)

            case let .tabContent(
                tabID,
                .entryViewLayout(.entryOperations(.undoRedo(.requestRedo))),
            ):
                requestNativeUndoRedoEffect(tabID: tabID, isUndo: false, state: state)

            default:
                .none
            }
        }
    }

    private func undoManagerScope(tabID: ContentTabID, state: State) -> UndoManagerScope? {
        guard let windowID = state.windowID else { return nil }
        return UndoManagerScope(windowID: windowID, contentTabID: tabID.rawValue)
    }

    private func tabContentState(tabID: ContentTabID, state: State) -> FileManagerContentState? {
        guard state.contentTabs.tabs[id: tabID] != nil else { return nil }
        if state.contentTabs.activeTabID == tabID {
            return state.content
        }
        return state.tabContentStates[tabID]
    }

    private func registerNativeUndoEffect(
        tabID: ContentTabID,
        record: EntryActionRecord,
        generation: FileOperationUndoManagerClient.Generation?,
        state: State,
    ) -> Effect<Action> {
        guard record.operationKind.isUndoable,
              tabContentState(tabID: tabID, state: state) != nil,
              let scope = undoManagerScope(tabID: tabID, state: state),
              let generation
        else { return .none }

        let client = fileOperationUndoManagerClient
        return .run { send in
            let (events, continuation) = AsyncStream<FileOperationNativeUndoEvent>.makeStream()
            defer { continuation.finish() }
            let didRegister = await client.registerUndo(
                scope,
                generation,
                record,
                { continuation.yield(.undo($0)) },
                { continuation.yield(.redo($0)) },
            )
            guard didRegister else { return }

            for await event in events {
                guard await client.isGenerationCurrent(scope, generation) else { return }
                let action: EntryOperationsAction.UndoRedo = switch event {
                case let .undo(record):
                    .undoEntryAction(record)
                case let .redo(record):
                    .redoEntryAction(record)
                }
                await send(.tabContent(
                    tabID: tabID,
                    action: .entryViewLayout(.entryOperations(.undoRedo(action))),
                ))
            }
        }
        .cancellable(id: FileOperationUndoRegistrationCancelID(scope: scope))
    }

    private func requestNativeUndoRedoEffect(
        tabID: ContentTabID,
        isUndo: Bool,
        state: State,
    ) -> Effect<Action> {
        guard let content = tabContentState(tabID: tabID, state: state),
              let scope = undoManagerScope(tabID: tabID, state: state)
        else { return .none }

        let operations = content.entryViewLayout.entryOperations
        guard isUndo ? operations.canUndoEntryAction : operations.canRedoEntryAction else {
            return .none
        }

        let client = fileOperationUndoManagerClient
        return .run { _ in
            if isUndo {
                _ = await client.requestUndo(scope)
            } else {
                _ = await client.requestRedo(scope)
            }
        }
    }
}

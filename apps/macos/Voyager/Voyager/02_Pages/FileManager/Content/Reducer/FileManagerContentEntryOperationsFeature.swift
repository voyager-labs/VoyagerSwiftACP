import ComposableArchitecture

@Reducer
struct FileManagerContentEntryOperationsFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            guard case let .entryOperations(entryOperationsAction) = action else {
                return .none
            }

            return handleEntryOperationsAction(entryOperationsAction)
        }
    }

    private func handleEntryOperationsAction(
        _ action: EntryOperationsAction,
    ) -> Effect<Action> {
        switch action {
        case let .operationFinished(filePath, kind, result):
            .send(.entries(.operationFinished(filePath, kind, result)))

        case .emptyTrashCompleted:
            .send(.emptyTrashCompleted)

        default:
            .none
        }
    }
}

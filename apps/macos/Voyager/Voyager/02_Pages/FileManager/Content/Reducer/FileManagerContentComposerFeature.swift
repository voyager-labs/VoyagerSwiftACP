import ComposableArchitecture

@Reducer
struct FileManagerContentComposerFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.collectionAlertClient)
    private var collectionAlertClient
    @Dependency(\.fileManagerClient)
    private var fileManagerClient: FileManagerClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .composer(composerAction) = action else {
                return .none
            }

            return FileManagerContentComposerCoordinator.reduce(
                composerAction,
                state: &state,
                dependencies: .init(
                    collectionAlertClient: collectionAlertClient,
                    computerName: fileManagerClient.displayName("/"),
                ),
            )
        }
    }
}

import ComposableArchitecture

@Reducer
struct FileManagerContentFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient

    var body: some Reducer<State, Action> {
        Scope(state: \.composer, action: \.composer) {
            ComposerFeature()
        }

        Scope(state: \.entryViewLayout, action: \.entryViewLayout) {
            EntryViewLayoutFeature()
        }

        Scope(state: \.entryOperations, action: \.entryOperations) {
            EntryOperationsFeature()
        }

        Scope(state: \.entryArrangements, action: \.entryArrangements) {
            EntryArrangementsFeature()
        }

        FileManagerEntryArrangementsBridge()

        EntryCommandRoutingReducer()
        FileManagerContentEntryAppearanceFeature()
        FileManagerContentEntryOperationsFeature()
        FileManagerContentEntryThumbnailFeature()
        FileManagerContentComposerFeature()
        FileManagerContentCollectionDraftFeature()

        Reduce { state, action in
            switch action {
            case let .handleKeyCommand(command):
                return FileManagerContentKeyCommandHandler.effect(for: command, state: state)

            case .openPathInNewWindow,
                 .openPathInNewTab:
                return .none

            case let .changeLayout(layout):
                state.viewLayout = layout
                state.syncComposerCollectionState()
                userDefaultsClient.setString(layout.rawValue, SettingsKeys.viewLayout)
                return .none

            case let .saveScrollOffset(offset, forPath: path):
                state.navigation.scrollPositions[path] = offset
                return .none

            default:
                return .none
            }
        }
    }
}

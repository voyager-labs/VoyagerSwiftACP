import ComposableArchitecture

@Reducer
struct FileManagerContentEntryAppearanceFeature {
    typealias State = FileManagerContentState
    typealias Action = FileManagerContentAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            guard case let .entries(entryAction) = action else {
                return .none
            }

            switch entryAction {
            case let .setListIconSize(size):
                state.listIconSize = size
                return .none

            case let .setGridIconSize(size):
                state.gridIconSize = size
                return .none

            case let .setListTextSize(size):
                state.listTextSize = size
                return .none

            case let .setGridTextSize(size):
                state.gridTextSize = size
                return .none

            default:
                return .none
            }
        }
    }
}

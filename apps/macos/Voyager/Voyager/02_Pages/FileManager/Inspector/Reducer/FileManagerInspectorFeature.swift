import ComposableArchitecture

@Reducer
struct FileManagerInspectorFeature {
    typealias State = FileManagerInspectorState
    typealias Action = FileManagerInspectorAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .toggleInspector:
                state.inspectorVisible.toggle()
                return .none

            case let .setInspectorPaneExists(exists):
                state.inspectorPaneExists = exists
                return .none
            }
        }
    }
}

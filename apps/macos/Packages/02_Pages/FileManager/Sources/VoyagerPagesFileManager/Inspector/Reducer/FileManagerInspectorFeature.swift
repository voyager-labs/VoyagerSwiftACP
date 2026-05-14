import ComposableArchitecture

@Reducer
public struct FileManagerInspectorFeature {
    public typealias State = FileManagerInspectorState
    public typealias Action = FileManagerInspectorAction

    public var body: some Reducer<State, Action> {
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

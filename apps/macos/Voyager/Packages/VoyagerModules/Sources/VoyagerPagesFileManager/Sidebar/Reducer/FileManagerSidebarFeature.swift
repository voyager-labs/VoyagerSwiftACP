import ComposableArchitecture

@Reducer
public struct FileManagerSidebarFeature {
    public typealias State = FileManagerSidebarState
    public typealias Action = FileManagerSidebarAction

    public init() {}

    public var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarSourceLoadingReducer()
        FileManagerSidebarInteractionReducer()
    }
}

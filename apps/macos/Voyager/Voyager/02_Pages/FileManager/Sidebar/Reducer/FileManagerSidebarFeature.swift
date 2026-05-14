import ComposableArchitecture

@Reducer
struct FileManagerSidebarFeature {
    typealias State = FileManagerSidebarState
    typealias Action = FileManagerSidebarAction

    var body: some Reducer<State, Action> {
        FileManagerSidebarPreferenceReducer()
        FileManagerSidebarSourceLoadingReducer()
        FileManagerSidebarInteractionReducer()
    }
}

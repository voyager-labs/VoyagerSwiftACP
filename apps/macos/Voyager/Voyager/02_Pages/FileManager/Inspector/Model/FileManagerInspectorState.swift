import ComposableArchitecture

@ObservableState
struct FileManagerInspectorState: Equatable {
    var inspectorVisible: Bool = false
    var inspectorPaneExists: Bool = false
}

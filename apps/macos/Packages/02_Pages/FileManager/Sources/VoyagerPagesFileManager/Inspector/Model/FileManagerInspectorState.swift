import ComposableArchitecture

@ObservableState
public struct FileManagerInspectorState: Equatable {
    var inspectorVisible: Bool = false
    var inspectorPaneExists: Bool = false
}

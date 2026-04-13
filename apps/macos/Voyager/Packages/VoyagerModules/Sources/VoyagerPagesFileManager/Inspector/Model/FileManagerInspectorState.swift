import ComposableArchitecture

@ObservableState
public struct FileManagerInspectorState: Equatable {
    public var inspectorVisible: Bool = false
    public var inspectorPaneExists: Bool = false
}

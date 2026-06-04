struct InspectorMountViewState: Equatable {
    let inspectorVisible: Bool
    let inspectorPaneExists: Bool
    let activeMode: FileManagerInspectorMode

    init(state: FileManagerWindowState) {
        inspectorVisible = state.inspector.inspectorVisible
        inspectorPaneExists = state.inspector.inspectorPaneExists
        activeMode = state.inspector.activeMode
    }
}

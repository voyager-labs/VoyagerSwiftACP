import ComposableArchitecture

@CasePathable
enum FileManagerInspectorAction: CasePathable, Sendable {
    case toggleInspector
    case setInspectorPaneExists(Bool)
}

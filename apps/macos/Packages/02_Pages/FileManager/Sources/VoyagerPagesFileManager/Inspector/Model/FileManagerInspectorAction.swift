import ComposableArchitecture

@CasePathable
public enum FileManagerInspectorAction: CasePathable, Sendable {
    case toggleInspector
    case setInspectorPaneExists(Bool)
}

import ComposableArchitecture

@CasePathable
enum FileManagerContentDelegateAction: CasePathable, Sendable {
    case closeWindowRequested
}

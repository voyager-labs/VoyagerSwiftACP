import ComposableArchitecture

@CasePathable
enum FileManagerContentCollectionDraftAction: CasePathable, Sendable {
    case discardChangesTapped
}

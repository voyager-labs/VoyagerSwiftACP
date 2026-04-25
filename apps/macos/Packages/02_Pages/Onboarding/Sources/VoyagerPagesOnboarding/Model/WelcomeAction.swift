import ComposableArchitecture

@CasePathable
enum WelcomeAction: CasePathable, Sendable {
    case setCompleted(Bool)
}

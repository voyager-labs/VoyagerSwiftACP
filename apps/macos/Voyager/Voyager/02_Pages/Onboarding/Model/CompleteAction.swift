import ComposableArchitecture

@CasePathable
enum CompleteAction: CasePathable, Sendable {
    case startUsingTapped
    case retryTapped
    case openWindowResponse(Bool)
}

import ComposableArchitecture

@CasePathable
enum CompleteAction: CasePathable {
    case startUsingTapped
    case retryTapped
    case openWindowResponse(Bool)
}

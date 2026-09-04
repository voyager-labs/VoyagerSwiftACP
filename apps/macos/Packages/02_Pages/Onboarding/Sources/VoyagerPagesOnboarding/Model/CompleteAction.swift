import ComposableArchitecture
import Foundation

@CasePathable
enum CompleteAction: CasePathable, Equatable {
    case startUsingTapped
    case retryTapped
    case progressSaveResponse(UUID, Bool)
    case openWindowResponse(UUID, Bool)
}

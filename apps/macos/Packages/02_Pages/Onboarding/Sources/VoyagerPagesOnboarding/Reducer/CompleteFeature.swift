import ComposableArchitecture
import Foundation

@Reducer
struct CompleteFeature {
    typealias State = CompleteState
    typealias Action = CompleteAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startUsingTapped, .retryTapped:
                state.isComplete = true
                state.isOpeningWindow = true
                state.openWindowError = nil
                return .none

            case let .openWindowResponse(opened):
                state.isOpeningWindow = false
                if !opened {
                    state.openWindowError = "We couldn't open a file manager window. Please try again."
                }
                return .none
            }
        }
    }
}

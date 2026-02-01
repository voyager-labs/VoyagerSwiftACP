import ComposableArchitecture
import Foundation

@Reducer
struct CompleteFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var isComplete: Bool = false
        var isOpeningWindow: Bool = false
        var openWindowError: String?
    }

    enum Action: Sendable {
        case startUsingTapped
        case retryTapped
        case openWindowResponse(Bool)
    }

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

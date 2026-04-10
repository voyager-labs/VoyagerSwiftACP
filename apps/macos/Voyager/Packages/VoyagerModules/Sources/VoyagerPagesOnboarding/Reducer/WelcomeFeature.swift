import ComposableArchitecture
import Foundation

@Reducer
struct WelcomeFeature {
    typealias State = WelcomeState
    typealias Action = WelcomeAction

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setCompleted(isComplete):
                state.isComplete = isComplete
                return .none
            }
        }
    }
}

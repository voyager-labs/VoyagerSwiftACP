import ComposableArchitecture
import Foundation

@Reducer
struct WelcomeFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var isComplete: Bool = true
    }

    enum Action: Sendable {
        case setCompleted(Bool)
    }

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

import ComposableArchitecture
import Foundation

@Reducer
struct CompleteFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var isComplete: Bool = false
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

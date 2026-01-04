import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var stepIndex: Int = 1
        var totalSteps: Int = 5
    }

    enum Action: Sendable {
        case onAppear
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .onAppear:
                .none
            }
        }
    }
}

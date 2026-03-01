import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    typealias State = OnboardingState
    typealias Action = OnboardingAction

    @Dependency(\.onboardingProgressClient)
    var onboardingProgressClient

    var body: some Reducer<State, Action> {
        Scope(state: \.welcome, action: \.welcome) {
            WelcomeFeature()
        }
        Scope(state: \.betaAccess, action: \.betaAccess) {
            BetaAccessFeature()
        }
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }
        Scope(state: \.complete, action: \.complete) {
            CompleteFeature()
        }

        Reduce { state, action in
            let progressClient = onboardingProgressClient

            switch action {
            case .onAppear:
                switch progressClient.load() {
                case .empty:
                    state = State()
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressClient.save(snapshot)
                    }

                case .resetRequired:
                    state = State()
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressClient.reset()
                        progressClient.save(snapshot)
                    }

                case let .success(snapshot):
                    state.applyStepState(snapshot.stepState)
                    state.currentStep = state.lastValidStep(from: snapshot.currentStep)
                    let updatedSnapshot = state.progressSnapshot
                    return .run { _ in
                        progressClient.save(updatedSnapshot)
                    }
                }

            case .backTapped:
                guard let previous = state.currentStep.previous else { return .none }
                state.currentStep = previous
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressClient.save(snapshot)
                }

            case .nextTapped:
                guard state.canGoNext, let next = state.currentStep.next else { return .none }
                state.currentStep = next
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressClient.save(snapshot)
                }

            case .welcome, .betaAccess, .permissions, .complete:
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressClient.save(snapshot)
                }
            }
        }
    }
}

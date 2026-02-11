import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    typealias State = OnboardingState
    typealias Action = OnboardingAction

    @Dependency(\.onboardingProgressStore)
    var onboardingProgressStore
    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient

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
            let progressStore = onboardingProgressStore

            switch action {
            case .onAppear:
                switch progressStore.load() {
                case .empty:
                    state = State()
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressStore.save(snapshot)
                    }

                case .resetRequired:
                    state = State()
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressStore.reset()
                        progressStore.save(snapshot)
                    }

                case let .success(snapshot):
                    state.applyStepState(snapshot.stepState)
                    state.currentStep = state.lastValidStep(from: snapshot.currentStep)
                    let updatedSnapshot = state.progressSnapshot
                    return .run { _ in
                        progressStore.save(updatedSnapshot)
                    }
                }

            case .backTapped:
                guard let previous = state.currentStep.previous else { return .none }
                state.currentStep = previous
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressStore.save(snapshot)
                }

            case .nextTapped:
                guard state.canGoNext, let next = state.currentStep.next else { return .none }
                state.currentStep = next
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressStore.save(snapshot)
                }

            case .complete(.startUsingTapped), .complete(.retryTapped):
                let snapshot = state.progressSnapshot
                state.complete.openWindowError = nil
                return .run { [onboardingProgressStore, onboardingWindowClient] send in
                    onboardingProgressStore.save(snapshot)
                    let path = await MainActor.run {
                        SettingsDefaults.defaultTabPath()
                    }
                    let opened = await onboardingWindowClient.openMainWindow(path)
                    await send(.complete(.openWindowResponse(opened)))
                }

            case let .complete(.openWindowResponse(opened)):
                let snapshot = state.progressSnapshot
                let saveEffect: Effect<Action> = .run { _ in
                    progressStore.save(snapshot)
                }
                let closeEffect: Effect<Action> = if opened {
                    .run { [onboardingWindowClient] _ in
                        await onboardingWindowClient.closeWindow()
                    }
                } else {
                    .none
                }
                return .merge(saveEffect, closeEffect)

            case .welcome, .betaAccess, .permissions, .complete:
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressStore.save(snapshot)
                }
            }
        }
    }
}

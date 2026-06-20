import ComposableArchitecture
import Foundation
import VoyagerFeaturesAccountAccess

@Reducer
struct OnboardingFeature {
    typealias State = OnboardingState
    typealias Action = OnboardingAction

    @Dependency(\.onboardingProgressClient)
    var onboardingProgressClient

    @Dependency(\.onboardingWindowClient)
    var onboardingWindowClient

    var body: some Reducer<State, Action> {
        Scope(state: \.welcome, action: \.welcome) {
            WelcomeFeature()
        }
        Scope(state: \.accessUnlock, action: \.accessUnlock) {
            AccountAccessFeature()
        }
        Scope(state: \.permissions, action: \.permissions) {
            PermissionsFeature()
        }
        Scope(state: \.aiProviderSetup, action: \.aiProviderSetup) {
            AiProviderSetupFeature()
        }
        Scope(state: \.complete, action: \.complete) {
            CompleteFeature()
        }

        Reduce { state, action in
            progressReduce(state: &state, action: action)
        }
    }

    private func progressReduce(
        state: inout State, action: Action,
    ) -> Effect<Action> {
        let progressClient = onboardingProgressClient

        switch action {
        case .onAppear:
            switch progressClient.load() {
            case .empty:
                state = State()
                let snapshot = state.progressSnapshot
                return Self.saveEffect(snapshot, progressClient: progressClient)

            case .resetRequired:
                state = State()
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressClient.reset()
                    _ = progressClient.save(snapshot)
                }

            case let .success(snapshot):
                state.applyStepState(snapshot.stepState)
                if snapshot.stepState.accessUnlockComplete, snapshot.accessSnapshot == nil {
                    state.accessUnlock = AccountAccessFeature.State()
                    state.currentStep = .accessUnlock
                    let updatedSnapshot = state.progressSnapshot
                    return .run { _ in
                        _ = progressClient.save(updatedSnapshot)
                    }
                }
                if let accessSnapshot = snapshot.accessSnapshot {
                    state.accessUnlock.snapshot = accessSnapshot
                    state.accessUnlock.status = accessSnapshot.status
                }
                state.currentStep = state.lastValidStep(from: snapshot.currentStep)
                let updatedSnapshot = state.progressSnapshot
                let saveEffect: Effect<Action> = .run { _ in
                    _ = progressClient.save(updatedSnapshot)
                }
                guard snapshot.accessSnapshot != nil, state.accessUnlock.isComplete else {
                    return saveEffect
                }
                return .concatenate(
                    saveEffect,
                    .send(.accessUnlock(.onAppear)),
                )
            }

        case .backTapped:
            guard let previous = state.currentStep.previous else { return .none }
            state.currentStep = previous
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)

        case .nextTapped:
            guard state.canGoNext, let next = state.currentStep.next else { return .none }
            state.currentStep = next
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)

        case .complete(.startUsingTapped), .complete(.retryTapped):
            let snapshot = state.progressSnapshot
            return .run { send in
                _ = progressClient.save(snapshot)
                let opened = await onboardingWindowClient.openMainWindow(.defaultTabPath)
                await send(.complete(.openWindowResponse(opened)))
            }

        case .complete(.openWindowResponse(true)):
            return .run { _ in
                await onboardingWindowClient.closeWindow()
            }

        case .complete(.openWindowResponse(false)):
            return .none

        case .aiProviderSetup(.setUpLaterTapped):
            var skippedSetup = state.aiProviderSetup
            skippedSetup.choice = .setUpLater
            skippedSetup.loadError = nil
            skippedSetup.refreshStatus()

            var snapshotState = state
            snapshotState.aiProviderSetup = skippedSetup
            let snapshot = snapshotState.progressSnapshot

            switch progressClient.save(snapshot) {
            case .success:
                state.aiProviderSetup = skippedSetup
            case .failure:
                state.aiProviderSetup.choice = .none
                state.aiProviderSetup.loadError = "Failed to save onboarding progress."
                state.aiProviderSetup.refreshStatus()
            }
            return .none

        case let .accessUnlock(.accessStatusResponse(generation: _, result: .success(response))):
            if !response.status.isActive {
                state.currentStep = .accessUnlock
            }
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)

        case .welcome, .accessUnlock, .permissions, .aiProviderSetup, .complete:
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)
        }
    }

    private static func saveEffect(
        _ snapshot: OnboardingProgressSnapshot,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        .run { _ in
            _ = progressClient.save(snapshot)
        }
    }
}

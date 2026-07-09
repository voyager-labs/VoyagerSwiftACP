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
            return handleOnAppear(state: &state, progressClient: progressClient)

        case .backTapped:
            return handleBackTapped(state: &state, progressClient: progressClient)

        case .nextTapped:
            return handleNextTapped(state: &state, progressClient: progressClient)

        case .complete(.startUsingTapped), .complete(.retryTapped):
            return handleCompleteStart(state: &state, progressClient: progressClient)

        case .complete(.openWindowResponse(true)):
            return .run { _ in
                await onboardingWindowClient.closeWindow()
            }

        case .complete(.openWindowResponse(false)):
            return .none

        case .aiProviderSetup(.setUpLaterTapped):
            return handleSetUpLaterTapped(state: &state, progressClient: progressClient)

        case let .accessUnlock(.accessStatusResponse(generation: _, result: .success(response))):
            return handleAccessStatusSuccess(response, state: &state, progressClient: progressClient)

        case .accessUnlock(._onAppearSessionRestored(nil)), .accessUnlock(._sessionExpiredDetected):
            state.currentStep = .accessUnlock
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)

        case .welcome, .accessUnlock, .permissions, .aiProviderSetup, .complete:
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)
        }
    }

    private func handleOnAppear(
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
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
            return handleLoadedProgress(snapshot, state: &state, progressClient: progressClient)
        }
    }

    private func handleLoadedProgress(
        _ snapshot: OnboardingProgressSnapshot,
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        let trustedAccessSnapshot = Self.trustedAccessSnapshot(snapshot.accessSnapshot)
        var trustedStepState = snapshot.stepState
        if snapshot.stepState.accessUnlockComplete, trustedAccessSnapshot == nil {
            trustedStepState.accessUnlockComplete = false
        }
        state.applyStepState(trustedStepState)
        if snapshot.stepState.accessUnlockComplete, trustedAccessSnapshot == nil {
            state.accessUnlock = AccountAccessFeature.State()
            state.currentStep = .accessUnlock
            let updatedSnapshot = state.progressSnapshot
            return Self.saveEffect(updatedSnapshot, progressClient: progressClient)
        }
        if let accessSnapshot = trustedAccessSnapshot {
            state.accessUnlock.snapshot = accessSnapshot
            state.accessUnlock.status = accessSnapshot.status
        }
        state.currentStep = state.lastValidStep(from: snapshot.currentStep)
        let saveEffect = Self.saveEffect(state.progressSnapshot, progressClient: progressClient)
        guard trustedAccessSnapshot != nil, state.accessUnlock.isComplete else { return saveEffect }
        return .concatenate(saveEffect, .send(.accessUnlock(.onAppear)))
    }

    private func handleNextTapped(
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        guard state.canGoNext, let next = state.currentStep.next else { return .none }
        state.currentStep = next
        let snapshot = state.progressSnapshot
        return Self.saveEffect(snapshot, progressClient: progressClient)
    }

    private func handleCompleteStart(
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        let snapshot = state.progressSnapshot
        return .run { send in
            _ = progressClient.save(snapshot)
            let opened = await onboardingWindowClient.openMainWindow(.defaultTabPath)
            await send(.complete(.openWindowResponse(opened)))
        }
    }

    private func handleSetUpLaterTapped(
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
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
    }

    private func handleAccessStatusSuccess(
        _ response: AccessStatusResponse,
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        if !response.toAccessStatus().isActive {
            state.currentStep = .accessUnlock
        }
        let snapshot = state.progressSnapshot
        return Self.saveEffect(snapshot, progressClient: progressClient)
    }

    private func handleBackTapped(
        state: inout State,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        guard let previous = state.currentStep.previous else { return .none }
        let shouldCancelSignIn = state.currentStep == .accessUnlock
            && (state.accessUnlock.isSignInInProgress || state.accessUnlock.handoffPendingState != nil)
        state.currentStep = previous
        guard shouldCancelSignIn else {
            let snapshot = state.progressSnapshot
            return Self.saveEffect(snapshot, progressClient: progressClient)
        }
        return .send(.accessUnlock(.cancelSignIn))
    }

    private static func saveEffect(
        _ snapshot: OnboardingProgressSnapshot,
        progressClient: OnboardingProgressClient,
    ) -> Effect<Action> {
        .run { _ in
            _ = progressClient.save(snapshot)
        }
    }

    private static func trustedAccessSnapshot(_ snapshot: AccessStatusSnapshot?) -> AccessStatusSnapshot? {
        guard let snapshot else { return nil }
        if snapshot.status.isActive, !snapshot.isDeviceBindingVerified {
            return nil
        }
        return snapshot
    }
}

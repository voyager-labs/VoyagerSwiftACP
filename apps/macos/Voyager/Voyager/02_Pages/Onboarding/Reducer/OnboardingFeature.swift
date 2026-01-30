import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var currentStep: OnboardingStep = .welcome

        var welcome = WelcomeFeature.State()
        var betaAccess = BetaAccessFeature.State()
        var permissions = PermissionsFeature.State()
        var complete = CompleteFeature.State()

        var totalSteps: Int {
            OnboardingStep.allCases.count
        }

        var currentStepIndex: Int {
            currentStep.index + 1
        }

        var canGoBack: Bool {
            currentStep.previous != nil
        }

        var canGoNext: Bool {
            currentStep.next != nil && isStepComplete(currentStep)
        }

        var isSessionComplete: Bool {
            complete.isComplete
        }

        var progressSnapshot: OnboardingProgressSnapshot {
            OnboardingProgressSnapshot(
                currentStep: currentStep,
                stepState: OnboardingStepState(
                    welcomeComplete: welcome.isComplete,
                    betaAccessComplete: betaAccess.isComplete,
                    permissionsComplete: permissions.isComplete,
                    completeComplete: complete.isComplete,
                ),
            )
        }

        func isStepComplete(_ step: OnboardingStep) -> Bool {
            switch step {
            case .welcome:
                welcome.isComplete
            case .betaAccess:
                betaAccess.isComplete
            case .permissions:
                permissions.isComplete
            case .complete:
                complete.isComplete
            }
        }

        mutating func applyStepState(_ stepState: OnboardingStepState) {
            welcome.isComplete = stepState.welcomeComplete
            betaAccess.isComplete = stepState.betaAccessComplete
            betaAccess.isVerifying = false
            if betaAccess.isComplete {
                betaAccess.status = .active
                betaAccess.reason = .none
            } else {
                betaAccess.status = .notActive
                betaAccess.reason = .missingInput
            }
            permissions.isComplete = stepState.permissionsComplete
            complete.isComplete = stepState.completeComplete
        }

        func lastValidStep(from step: OnboardingStep) -> OnboardingStep {
            var candidate = step
            while !isStepComplete(candidate) {
                guard let previous = candidate.previous else {
                    return .welcome
                }
                candidate = previous
            }
            return candidate
        }
    }

    enum Action: Sendable {
        case onAppear
        case backTapped
        case nextTapped

        case welcome(WelcomeFeature.Action)
        case betaAccess(BetaAccessFeature.Action)
        case permissions(PermissionsFeature.Action)
        case complete(CompleteFeature.Action)
    }

    @Dependency(\.onboardingProgressStore)
    var onboardingProgressStore
    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
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
                return .run { [onboardingProgressStore, fileManagerWindowClient] send in
                    onboardingProgressStore.save(snapshot)
                    let path = await MainActor.run {
                        SettingsDefaults.defaultTabPath()
                    }
                    let opened = await fileManagerWindowClient.openWindow(path)
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

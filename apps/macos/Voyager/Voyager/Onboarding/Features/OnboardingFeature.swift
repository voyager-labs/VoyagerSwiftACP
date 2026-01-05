import ComposableArchitecture
import Foundation

@Reducer
struct OnboardingFeature {
    @ObservableState
    struct State: Equatable {
        var currentStep: OnboardingStep = .welcome
        var showResumeBanner: Bool = false

        var welcome = WelcomeFeature.State()
        var betaAccess = BetaAccessFeature.State()
        var permissions = PermissionsFeature.State()
        var indexingPreset = IndexingPresetFeature.State()
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
                    indexingPresetComplete: indexingPreset.isComplete,
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
            case .indexingPreset:
                indexingPreset.isComplete
            case .complete:
                complete.isComplete
            }
        }

        mutating func applyStepState(_ stepState: OnboardingStepState) {
            welcome.isComplete = stepState.welcomeComplete
            betaAccess.isComplete = stepState.betaAccessComplete
            permissions.isComplete = stepState.permissionsComplete
            indexingPreset.isComplete = stepState.indexingPresetComplete
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
        case dismissResumeBanner

        case welcome(WelcomeFeature.Action)
        case betaAccess(BetaAccessFeature.Action)
        case permissions(PermissionsFeature.Action)
        case indexingPreset(IndexingPresetFeature.Action)
        case complete(CompleteFeature.Action)
    }

    @Dependency(\.onboardingProgressStore)
    var onboardingProgressStore

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
        Scope(state: \.indexingPreset, action: \.indexingPreset) {
            IndexingPresetFeature()
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
                    state.showResumeBanner = false
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressStore.save(snapshot)
                    }

                case .resetRequired:
                    state = State()
                    state.showResumeBanner = false
                    let snapshot = state.progressSnapshot
                    return .run { _ in
                        progressStore.reset()
                        progressStore.save(snapshot)
                    }

                case let .success(snapshot):
                    state.applyStepState(snapshot.stepState)
                    state.currentStep = state.lastValidStep(from: snapshot.currentStep)
                    state.showResumeBanner = !state.isSessionComplete
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

            case .dismissResumeBanner:
                state.showResumeBanner = false
                return .none

            case .welcome, .betaAccess, .permissions, .indexingPreset, .complete:
                let snapshot = state.progressSnapshot
                return .run { _ in
                    progressStore.save(snapshot)
                }
            }
        }
    }
}

import ComposableArchitecture

@ObservableState
struct OnboardingState: Equatable {
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

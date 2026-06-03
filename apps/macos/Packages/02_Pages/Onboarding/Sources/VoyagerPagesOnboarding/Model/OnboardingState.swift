import ComposableArchitecture
import VoyagerFeaturesBetaAccess

@ObservableState
struct OnboardingState: Equatable {
    var currentStep: OnboardingStep = .welcome

    var welcome: WelcomeFeature.State = .init()
    var betaAccess: BetaAccessFeature.State = .init()
    var permissions: PermissionsFeature.State = .init()
    var complete: CompleteFeature.State = .init()

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
                betaAccessEmail: betaAccess.isComplete ? betaAccess.email : nil,
                betaAccessToken: betaAccess.isComplete ? betaAccess.token : nil,
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
            if let email = stepState.betaAccessEmail, !email.isEmpty {
                betaAccess.email = email
            }
            if let token = stepState.betaAccessToken, !token.isEmpty {
                betaAccess.token = token
            }
        } else {
            betaAccess.status = .notActive
            betaAccess.reason = .missingInput
        }
        permissions.isComplete = stepState.permissionsComplete
        complete.isComplete = stepState.completeComplete
    }

    func lastValidStep(from step: OnboardingStep) -> OnboardingStep {
        // If all prior required steps are complete, the persisted step is reachable —
        // return it directly even if the step itself is incomplete.
        if isPriorRequiredStepComplete(step) {
            return step
        }
        // Fallback: walk backwards to find the last completed step.
        var candidate = step
        while !isStepComplete(candidate) {
            guard let previous = candidate.previous else {
                return .welcome
            }
            candidate = previous
        }
        return candidate
    }

    /// Returns `true` when the immediate prior required step for the given step is complete.
    /// - `.welcome` has no prior requirements (always `true`).
    /// - `.betaAccess` requires `.welcome` complete.
    /// - `.permissions` requires `.betaAccess` complete.
    /// - `.complete` requires `.permissions` complete.
    private func isPriorRequiredStepComplete(_ step: OnboardingStep) -> Bool {
        guard let previous = step.previous else {
            return true
        }
        return isStepComplete(previous)
    }
}

import ComposableArchitecture
import VoyagerFeaturesAccountAccess

@ObservableState
struct OnboardingState: Equatable {
    var currentStep: OnboardingStep = .welcome

    var welcome: WelcomeFeature.State = .init()
    var accessUnlock: AccountAccessFeature.State = .init()
    var permissions: PermissionsFeature.State = .init()
    var aiProviderSetup: AiProviderSetupFeature.State = .init()
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
                accessUnlockComplete: accessUnlock.isComplete,
                permissionsComplete: permissions.isComplete,
                aiProviderSetupComplete: aiProviderSetup.isComplete,
                aiProviderSetupSkipped: aiProviderSetup.status == .skipped,
                aiProviderSetupChoice: aiProviderSetup.choice,
                aiProviderSetupStatus: aiProviderSetup.status,
                completeComplete: complete.isComplete,
            ),
            accessSnapshot: accessUnlock.snapshot,
        )
    }

    func isStepComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome:
            welcome.isComplete
        case .accessUnlock:
            accessUnlock.isComplete
        case .permissions:
            permissions.isComplete
        case .aiProviderSetup:
            aiProviderSetup.isComplete
        case .complete:
            complete.isComplete
        }
    }

    mutating func applyStepState(_ stepState: OnboardingStepState) {
        welcome.isComplete = stepState.welcomeComplete
        if stepState.accessUnlockComplete {
            accessUnlock.isComplete = true
            accessUnlock.isSubmitting = false
        } else {
            accessUnlock = AccountAccessFeature.State()
        }
        permissions.isComplete = stepState.permissionsComplete
        aiProviderSetup.choice = stepState.aiProviderSetupChoice
        aiProviderSetup.status = stepState.aiProviderSetupStatus
        aiProviderSetup.loadError = stepState.aiProviderSetupStatus == .error ? "Failed to load AI connections." : nil
        aiProviderSetup.refreshStatus()
        aiProviderSetup.status = stepState.aiProviderSetupStatus
        complete.isComplete = stepState.completeComplete
    }

    func lastValidStep(from step: OnboardingStep) -> OnboardingStep {
        // If all prior required steps are complete, the persisted step is reachable —
        // return it directly even if the step itself is incomplete.
        if isPriorRequiredStepComplete(step) {
            return step
        }
        // Fallback: walk backwards to find the first step whose entire prior chain is complete.
        var candidate = step
        while true {
            if isPriorRequiredStepComplete(candidate) {
                return candidate
            }
            guard let previous = candidate.previous else {
                return .welcome
            }
            candidate = previous
        }
    }

    /// Returns `true` when **all** prior required steps for the given step are complete.
    /// - `.welcome` has no prior requirements (always `true`).
    /// - `.accessUnlock` requires `.welcome` complete.
    /// - `.permissions` requires `.welcome` + `.accessUnlock` complete.
    /// - `.aiProviderSetup` requires `.welcome` + `.accessUnlock` + `.permissions` complete.
    /// - `.complete` requires `.welcome` + `.accessUnlock` + `.permissions` + `.aiProviderSetup` complete.
    private func isPriorRequiredStepComplete(_ step: OnboardingStep) -> Bool {
        // Walk the entire chain from .welcome up to (but not including) `step`.
        for priorStep in OnboardingStep.allCases {
            if priorStep == step { break }
            if !isStepComplete(priorStep) { return false }
        }
        return true
    }
}

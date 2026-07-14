import ComposableArchitecture

@ObservableState
struct OnboardingState: Equatable {
    var currentStep: OnboardingStep = .welcome
    var didBootstrapProgress = false

    var welcome: WelcomeFeature.State = .init()
    var access: OnboardingAccessProjection = .init()
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
                accessUnlockComplete: access.isComplete && access.hasAccountSession,
                permissionsComplete: permissions.isComplete,
                aiProviderSetupComplete: aiProviderSetup.isComplete,
                aiProviderSetupSkipped: aiProviderSetup.status == .skipped,
                aiProviderSetupChoice: aiProviderSetup.choice,
                aiProviderSetupStatus: aiProviderSetup.status,
                completeComplete: complete.isComplete,
            ),
            accessSnapshot: access.snapshot,
        )
    }

    func isStepComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome:
            welcome.isComplete
        case .accessUnlock:
            access.isComplete && access.hasAccountSession
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
        permissions.isComplete = stepState.permissionsComplete
        aiProviderSetup.choice = stepState.aiProviderSetupChoice
        aiProviderSetup.status = stepState.aiProviderSetupStatus
        aiProviderSetup.loadError = stepState.aiProviderSetupStatus == .error ? "Failed to load AI connections." : nil
        aiProviderSetup.refreshStatus()
        aiProviderSetup.status = stepState.aiProviderSetupStatus
        complete.isComplete = stepState.completeComplete
    }

    func lastValidStep(from step: OnboardingStep) -> OnboardingStep {
        if isPriorRequiredStepComplete(step) {
            return step
        }
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

    private func isPriorRequiredStepComplete(_ step: OnboardingStep) -> Bool {
        for priorStep in OnboardingStep.allCases {
            if priorStep == step { break }
            if !isStepComplete(priorStep) { return false }
        }
        return true
    }
}

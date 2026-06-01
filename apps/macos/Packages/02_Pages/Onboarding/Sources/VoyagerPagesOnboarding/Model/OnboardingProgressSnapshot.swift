import Foundation

nonisolated struct OnboardingStepState: Codable, Equatable {
    var welcomeComplete: Bool
    var betaAccessComplete: Bool
    var permissionsComplete: Bool
    var completeComplete: Bool

    init(
        welcomeComplete: Bool = true,
        betaAccessComplete: Bool = false,
        permissionsComplete: Bool = false,
        completeComplete: Bool = false,
    ) {
        self.welcomeComplete = welcomeComplete
        self.betaAccessComplete = betaAccessComplete
        self.permissionsComplete = permissionsComplete
        self.completeComplete = completeComplete
    }
}

nonisolated struct OnboardingProgressSnapshot: Equatable {
    var currentStep: OnboardingStep
    var stepState: OnboardingStepState
}

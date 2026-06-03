import Foundation

nonisolated struct OnboardingStepState: Codable, Equatable {
    var welcomeComplete: Bool
    var betaAccessComplete: Bool
    var permissionsComplete: Bool
    var completeComplete: Bool
    var betaAccessEmail: String?
    var betaAccessToken: String?

    init(
        welcomeComplete: Bool = true,
        betaAccessComplete: Bool = false,
        permissionsComplete: Bool = false,
        completeComplete: Bool = false,
        betaAccessEmail: String? = nil,
        betaAccessToken: String? = nil,
    ) {
        self.welcomeComplete = welcomeComplete
        self.betaAccessComplete = betaAccessComplete
        self.permissionsComplete = permissionsComplete
        self.completeComplete = completeComplete
        self.betaAccessEmail = betaAccessEmail
        self.betaAccessToken = betaAccessToken
    }
}

nonisolated struct OnboardingProgressSnapshot: Equatable {
    var currentStep: OnboardingStep
    var stepState: OnboardingStepState
}

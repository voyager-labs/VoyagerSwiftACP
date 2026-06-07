import Foundation

nonisolated struct OnboardingStepState: Codable, Equatable {
    var welcomeComplete: Bool
    var betaAccessComplete: Bool
    var permissionsComplete: Bool
    var aiProviderSetupComplete: Bool
    var aiProviderSetupSkipped: Bool
    var aiProviderSetupChoice: AiProviderSetupChoice
    var aiProviderSetupStatus: AiProviderSetupStatus
    var completeComplete: Bool
    var betaAccessEmail: String?
    var betaAccessToken: String?

    init(
        welcomeComplete: Bool = true,
        betaAccessComplete: Bool = false,
        permissionsComplete: Bool = false,
        aiProviderSetupComplete: Bool = false,
        aiProviderSetupSkipped: Bool = false,
        aiProviderSetupChoice: AiProviderSetupChoice = .none,
        aiProviderSetupStatus: AiProviderSetupStatus = .blocked,
        completeComplete: Bool = false,
        betaAccessEmail: String? = nil,
        betaAccessToken: String? = nil,
    ) {
        self.welcomeComplete = welcomeComplete
        self.betaAccessComplete = betaAccessComplete
        self.permissionsComplete = permissionsComplete
        self.aiProviderSetupComplete = aiProviderSetupComplete
        self.aiProviderSetupSkipped = aiProviderSetupSkipped
        self.aiProviderSetupChoice = aiProviderSetupChoice
        self.aiProviderSetupStatus = aiProviderSetupStatus
        self.completeComplete = completeComplete
        self.betaAccessEmail = betaAccessEmail
        self.betaAccessToken = betaAccessToken
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            welcomeComplete: container.decodeIfPresent(Bool.self, forKey: .welcomeComplete) ?? true,
            betaAccessComplete: container.decodeIfPresent(Bool.self, forKey: .betaAccessComplete) ?? false,
            permissionsComplete: container.decodeIfPresent(Bool.self, forKey: .permissionsComplete) ?? false,
            aiProviderSetupComplete: container.decodeIfPresent(Bool.self, forKey: .aiProviderSetupComplete) ?? false,
            aiProviderSetupSkipped: container.decodeIfPresent(Bool.self, forKey: .aiProviderSetupSkipped) ?? false,
            aiProviderSetupChoice: container.decodeIfPresent(
                AiProviderSetupChoice.self,
                forKey: .aiProviderSetupChoice,
            ) ?? .none,
            aiProviderSetupStatus: container.decodeIfPresent(
                AiProviderSetupStatus.self,
                forKey: .aiProviderSetupStatus,
            ) ?? .blocked,
            completeComplete: container.decodeIfPresent(Bool.self, forKey: .completeComplete) ?? false,
            betaAccessEmail: container.decodeIfPresent(String.self, forKey: .betaAccessEmail),
            betaAccessToken: container.decodeIfPresent(String.self, forKey: .betaAccessToken),
        )
    }

    private enum CodingKeys: String, CodingKey {
        case welcomeComplete
        case betaAccessComplete
        case permissionsComplete
        case aiProviderSetupComplete
        case aiProviderSetupSkipped
        case aiProviderSetupChoice
        case aiProviderSetupStatus
        case completeComplete
        case betaAccessEmail
        case betaAccessToken
    }
}

nonisolated struct OnboardingProgressSnapshot: Equatable {
    var currentStep: OnboardingStep
    var stepState: OnboardingStepState
}

import Foundation

nonisolated struct OnboardingStepState: Codable, Equatable {
    var welcomeComplete: Bool
    var permissionsComplete: Bool
    var aiProviderSetupComplete: Bool
    var aiProviderSetupSkipped: Bool
    var aiProviderSetupChoice: AiProviderSetupChoice
    var aiProviderSetupStatus: AiProviderSetupStatus
    var completeComplete: Bool

    init(
        welcomeComplete: Bool = true,
        permissionsComplete: Bool = false,
        aiProviderSetupComplete: Bool = false,
        aiProviderSetupSkipped: Bool = false,
        aiProviderSetupChoice: AiProviderSetupChoice = .none,
        aiProviderSetupStatus: AiProviderSetupStatus = .blocked,
        completeComplete: Bool = false,
    ) {
        self.welcomeComplete = welcomeComplete
        self.permissionsComplete = permissionsComplete
        self.aiProviderSetupComplete = aiProviderSetupComplete
        self.aiProviderSetupSkipped = aiProviderSetupSkipped
        self.aiProviderSetupChoice = aiProviderSetupChoice
        self.aiProviderSetupStatus = aiProviderSetupStatus
        self.completeComplete = completeComplete
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            welcomeComplete: container.decodeIfPresent(Bool.self, forKey: .welcomeComplete) ?? true,
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
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(welcomeComplete, forKey: .welcomeComplete)
        try container.encode(permissionsComplete, forKey: .permissionsComplete)
        try container.encode(aiProviderSetupComplete, forKey: .aiProviderSetupComplete)
        try container.encode(aiProviderSetupSkipped, forKey: .aiProviderSetupSkipped)
        try container.encode(aiProviderSetupChoice, forKey: .aiProviderSetupChoice)
        try container.encode(aiProviderSetupStatus, forKey: .aiProviderSetupStatus)
        try container.encode(completeComplete, forKey: .completeComplete)
    }

    private enum CodingKeys: String, CodingKey {
        case welcomeComplete
        case accessUnlockComplete
        /// 레거시 키 — 새 저장 데이터는 `.accessUnlockComplete` 사용
        case betaAccessComplete
        case permissionsComplete
        case aiProviderSetupComplete
        case aiProviderSetupSkipped
        case aiProviderSetupChoice
        case aiProviderSetupStatus
        case completeComplete
    }
}

nonisolated struct OnboardingProgressSnapshot: Equatable {
    var currentStep: OnboardingStep
    var stepState: OnboardingStepState
}

import ComposableArchitecture
import Foundation

nonisolated struct OnboardingStepState: Codable, Equatable, Sendable {
    var welcomeComplete: Bool
    var betaAccessComplete: Bool
    var permissionsComplete: Bool
    var indexingPresetComplete: Bool
    var completeComplete: Bool

    init(
        welcomeComplete: Bool = true,
        betaAccessComplete: Bool = false,
        permissionsComplete: Bool = false,
        indexingPresetComplete: Bool = false,
        completeComplete: Bool = false,
    ) {
        self.welcomeComplete = welcomeComplete
        self.betaAccessComplete = betaAccessComplete
        self.permissionsComplete = permissionsComplete
        self.indexingPresetComplete = indexingPresetComplete
        self.completeComplete = completeComplete
    }
}

nonisolated struct OnboardingProgressSnapshot: Equatable, Sendable {
    var currentStep: OnboardingStep
    var stepState: OnboardingStepState
}

struct OnboardingProgressStore: Sendable {
    enum LoadResult: Equatable, Sendable {
        case empty
        case resetRequired
        case success(OnboardingProgressSnapshot)
    }

    var load: @Sendable () -> LoadResult
    var save: @Sendable (OnboardingProgressSnapshot) -> Void
    var reset: @Sendable () -> Void
}

extension OnboardingProgressStore: DependencyKey {
    private nonisolated enum Keys {
        static let version = "onboardingProgressVersion"
        static let currentStep = "onboardingCurrentStep"
        static let stepState = "onboardingStepState"
    }

    nonisolated static let currentVersion = 1

    nonisolated static var liveValue: OnboardingProgressStore {
        OnboardingProgressStore(
            load: {
                let defaults = UserDefaults.standard

                guard let currentStepRaw = defaults.string(forKey: Keys.currentStep) else {
                    return .empty
                }
                guard let version = defaults.object(forKey: Keys.version) as? Int else {
                    return .resetRequired
                }
                guard version == currentVersion else {
                    return .resetRequired
                }
                guard let step = OnboardingStep(rawValue: currentStepRaw) else {
                    return .resetRequired
                }
                guard let data = defaults.data(forKey: Keys.stepState) else {
                    return .resetRequired
                }
                guard let stepState = try? JSONDecoder().decode(OnboardingStepState.self, from: data) else {
                    return .resetRequired
                }

                return .success(OnboardingProgressSnapshot(currentStep: step, stepState: stepState))
            },
            save: { snapshot in
                let defaults = UserDefaults.standard
                defaults.set(currentVersion, forKey: Keys.version)
                defaults.set(snapshot.currentStep.rawValue, forKey: Keys.currentStep)

                if let data = try? JSONEncoder().encode(snapshot.stepState) {
                    defaults.set(data, forKey: Keys.stepState)
                }
            },
            reset: {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Keys.version)
                defaults.removeObject(forKey: Keys.currentStep)
                defaults.removeObject(forKey: Keys.stepState)
            },
        )
    }

    nonisolated static var testValue: OnboardingProgressStore {
        OnboardingProgressStore(
            load: { .empty },
            save: { _ in },
            reset: {},
        )
    }

    nonisolated static var previewValue: OnboardingProgressStore {
        testValue
    }
}

extension DependencyValues {
    nonisolated var onboardingProgressStore: OnboardingProgressStore {
        get { self[OnboardingProgressStore.self] }
        set { self[OnboardingProgressStore.self] = newValue }
    }
}

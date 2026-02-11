import ComposableArchitecture
import Foundation

struct OnboardingProgressClient: Sendable {
    enum LoadResult: Equatable, Sendable {
        case empty
        case resetRequired
        case success(OnboardingProgressSnapshot)
    }

    var load: @Sendable () -> LoadResult
    var save: @Sendable (OnboardingProgressSnapshot) -> Void
    var reset: @Sendable () -> Void
}

extension OnboardingProgressClient: DependencyKey {
    private nonisolated enum Keys {
        static let version = "onboardingProgressVersion"
        static let currentStep = "onboardingCurrentStep"
        static let stepState = "onboardingStepState"
    }

    nonisolated static let currentVersion = 1.1

    nonisolated static var liveValue: OnboardingProgressClient {
        OnboardingProgressClient(
            load: {
                let defaults = UserDefaults.standard

                guard let currentStepRaw = defaults.string(forKey: Keys.currentStep) else {
                    return .empty
                }

                // Migration: Support both Int (legacy) and Double (current) version types
                let version: Double
                if let doubleVersion = defaults.object(forKey: Keys.version) as? Double {
                    version = doubleVersion
                } else if let intVersion = defaults.object(forKey: Keys.version) as? Int {
                    // Migrate from Int to Double
                    version = Double(intVersion)
                    defaults.set(version, forKey: Keys.version) // Update to Double
                } else {
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

    nonisolated static var testValue: OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .empty },
            save: { _ in },
            reset: {},
        )
    }

    nonisolated static var previewValue: OnboardingProgressClient {
        testValue
    }
}

extension DependencyValues {
    nonisolated var onboardingProgressClient: OnboardingProgressClient {
        get { self[OnboardingProgressClient.self] }
        set { self[OnboardingProgressClient.self] = newValue }
    }
}

import ComposableArchitecture
import Foundation
import VoyagerShared

struct OnboardingProgressClient {
    var load: @Sendable () -> LoadResult
    var save: @Sendable (OnboardingProgressSnapshot) -> SaveResult
    var reset: @Sendable () -> Void

    enum LoadResult: Equatable {
        case empty
        case resetRequired
        case success(OnboardingProgressSnapshot)
    }

    enum SaveResult: Equatable {
        case success
        case failure
    }
}

extension OnboardingProgressClient: DependencyKey {
    // swiftlint:disable:next modifier_order
    private nonisolated enum Keys {
        static let version = "onboardingProgressVersion"
        static let currentStep = "onboardingCurrentStep"
        static let stepState = "onboardingStepState"
    }

    nonisolated static let currentVersion = 1.2

    nonisolated static var liveValue: OnboardingProgressClient {
        OnboardingProgressClient(
            load: {
                @Dependency(\.userDefaultsClient)
                var userDefaultsClient

                guard let currentStepRaw = userDefaultsClient.string(Keys.currentStep) else {
                    return .empty
                }

                // Migration: Support both Int (legacy) and Double (current) version types
                let version: Double
                if let doubleVersion = userDefaultsClient.object(Keys.version) as? Double {
                    version = doubleVersion
                } else if let intVersion = userDefaultsClient.object(Keys.version) as? Int {
                    // Migrate from Int to Double
                    version = Double(intVersion)
                    userDefaultsClient.setObject(version, Keys.version) // Update to Double
                } else {
                    return .resetRequired
                }

                guard version == currentVersion else {
                    return .resetRequired
                }
                guard let step = OnboardingStep(rawValue: currentStepRaw) else {
                    return .resetRequired
                }
                guard let data = userDefaultsClient.object(Keys.stepState) as? Data else {
                    return .resetRequired
                }
                guard let stepState = try? JSONDecoder().decode(OnboardingStepState.self, from: data) else {
                    return .resetRequired
                }

                return .success(OnboardingProgressSnapshot(currentStep: step, stepState: stepState))
            },
            save: { snapshot in
                @Dependency(\.userDefaultsClient)
                var userDefaultsClient

                guard let data = try? JSONEncoder().encode(snapshot.stepState) else {
                    return .failure
                }

                userDefaultsClient.setObject(currentVersion, Keys.version)
                userDefaultsClient.setObject(snapshot.currentStep.rawValue, Keys.currentStep)
                userDefaultsClient.setObject(data, Keys.stepState)
                return .success
            },
            reset: {
                @Dependency(\.userDefaultsClient)
                var userDefaultsClient
                userDefaultsClient.setObject(nil, Keys.version)
                userDefaultsClient.setObject(nil, Keys.currentStep)
                userDefaultsClient.setObject(nil, Keys.stepState)
            },
        )
    }

    nonisolated static var testValue: OnboardingProgressClient {
        OnboardingProgressClient(
            load: { .empty },
            save: { _ in .success },
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

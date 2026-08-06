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
    nonisolated private enum Keys {
        static let version = "onboardingProgressVersion"
        static let currentStep = "onboardingCurrentStep"
        static let stepState = "onboardingStepState"
        static let legacyAccessSnapshot = "onboardingAccessSnapshot"
    }

    nonisolated static let currentVersion = 1.3

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

                guard let stepData = "\"\(currentStepRaw)\"".data(using: .utf8),
                      let step = try? JSONDecoder().decode(OnboardingStep.self, from: stepData)
                else {
                    return .resetRequired
                }
                guard let data = userDefaultsClient.object(Keys.stepState) as? Data else {
                    return .resetRequired
                }
                guard let stepState = try? JSONDecoder().decode(OnboardingStepState.self, from: data) else {
                    return .resetRequired
                }
                if version != currentVersion {
                    guard let snapshot = Self.migratedSnapshot(
                        version: version,
                        currentStep: step,
                        stepState: stepState,
                        rawStepValue: currentStepRaw,
                    ) else { return .resetRequired }
                    guard Self.persist(snapshot, userDefaultsClient: userDefaultsClient) == .success else {
                        return .resetRequired
                    }
                    return .success(snapshot)
                }

                userDefaultsClient.setObject(nil, Keys.legacyAccessSnapshot)
                return .success(OnboardingProgressSnapshot(
                    currentStep: step,
                    stepState: stepState,
                ))
            },
            save: { snapshot in
                @Dependency(\.userDefaultsClient)
                var userDefaultsClient

                return Self.persist(snapshot, userDefaultsClient: userDefaultsClient)
            },
            reset: {
                @Dependency(\.userDefaultsClient)
                var userDefaultsClient
                userDefaultsClient.setObject(nil, Keys.version)
                userDefaultsClient.setObject(nil, Keys.currentStep)
                userDefaultsClient.setObject(nil, Keys.stepState)
                userDefaultsClient.setObject(nil, Keys.legacyAccessSnapshot)
            },
        )
    }

    nonisolated static func migratedSnapshot(
        version: Double,
        currentStep: OnboardingStep,
        stepState: OnboardingStepState,
        rawStepValue: String? = nil,
    ) -> OnboardingProgressSnapshot? {
        var migratedStepState = stepState
        switch version {
        case 1.1:
            if migratedStepState.completeComplete {
                migratedStepState.aiProviderSetupComplete = true
                migratedStepState.aiProviderSetupSkipped = true
                migratedStepState.aiProviderSetupChoice = .setUpLater
                migratedStepState.aiProviderSetupStatus = .skipped
            }
        case 1.2:
            // v1.2에서 accessUnlock/betaAccess 레거시 rawValue가 permissions로
            // 디코딩된 경우에만 permissionsComplete 보정. 실제 permissions 단계에
            // 머물던 사용자의 진행 상태는 변경하지 않는다.
            let isLegacyAccessRaw = rawStepValue == "accessUnlock" || rawStepValue == "betaAccess"
            if isLegacyAccessRaw, !migratedStepState.permissionsComplete {
                migratedStepState.permissionsComplete = true
            }
        default:
            return nil
        }

        let migratedStep: OnboardingStep = switch currentStep {
        case .welcome, .permissions, .aiProviderSetup, .complete:
            currentStep
        }
        return OnboardingProgressSnapshot(
            currentStep: migratedStep,
            stepState: migratedStepState,
        )
    }

    nonisolated private static func persist(
        _ snapshot: OnboardingProgressSnapshot,
        userDefaultsClient: UserDefaultsClient,
    ) -> OnboardingProgressClient.SaveResult {
        guard let data = try? JSONEncoder().encode(snapshot.stepState) else {
            return .failure
        }

        userDefaultsClient.setObject(currentVersion, Keys.version)
        userDefaultsClient.setObject(snapshot.currentStep.rawValue, Keys.currentStep)
        userDefaultsClient.setObject(data, Keys.stepState)
        userDefaultsClient.setObject(nil, Keys.legacyAccessSnapshot)
        return .success
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

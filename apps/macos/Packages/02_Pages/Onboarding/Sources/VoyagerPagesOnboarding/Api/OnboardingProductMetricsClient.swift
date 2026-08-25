import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public enum OnboardingProductMetric: Equatable, Sendable {
    case completion(operationID: UUID, result: CompletionResult)
    case helperFolderAccess(operationID: UUID, result: PermissionResult)
    case fullDiskAccess(operationID: UUID, result: PermissionResult)
    case aiProvider(operationID: UUID, result: AIProviderResult)
    case aiProviderWithKind(operationID: UUID, provider: AIProviderKind?, result: AIProviderResult)
    public enum CompletionResult: String, Equatable, Sendable {
        case success
        case failure
    }

    public enum PermissionResult: String, Equatable, Sendable {
        case success
        case failure
        case unavailable
    }

    public enum AIProviderResult: String, Equatable, Sendable {
        case success
        case failure
        case skipped
    }

    public enum AIProviderKind: String, Equatable, Sendable {
        case chatgptCodex = "chatgpt_codex"
        case openai
        case anthropic

        init(provider: AiProvider) {
            switch provider {
            case .chatgptCodex: self = .chatgptCodex
            case .openai: self = .openai
            case .anthropic: self = .anthropic
            }
        }
    }
}

public struct OnboardingProductMetricsClient: Sendable {
    public var record: @Sendable (OnboardingProductMetric) -> Void

    public init(
        record: @escaping @Sendable (OnboardingProductMetric) -> Void = { _ in },
    ) {
        self.record = record
    }

    public static let liveValue = OnboardingProductMetricsClient()
    public static let testValue = OnboardingProductMetricsClient()

    public func record(_ metric: OnboardingProductMetric) {
        record(metric)
    }
}

extension OnboardingProductMetricsClient: DependencyKey {}

public extension DependencyValues {
    var onboardingProductMetricsClient: OnboardingProductMetricsClient {
        get { self[OnboardingProductMetricsClient.self] }
        set { self[OnboardingProductMetricsClient.self] = newValue }
    }
}

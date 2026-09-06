import ComposableArchitecture
import Foundation
import VoyagerEntitiesAi

public enum AiChatProductMetricResult: String, Equatable, Sendable {
    case success
    case failure
    case cancelled
    case unavailable
}

public enum AiChatProductMetricSourceSurface: String, Equatable, Sendable {
    case aiChatContent = "ai_chat_content"
    case aiChatInspector = "ai_chat_inspector"
}

public enum AiChatProductMetricInteractionIdentity: Equatable, Sendable {
    case generateContextualChatResponse
    case cancelActiveChatRequest
}

public enum AiChatProductMetric: Equatable, Sendable {
    case turnSubmitted(operationID: UUID, sourceSurface: AiChatProductMetricSourceSurface)
    case turnResult(
        operationID: UUID,
        interaction: AiChatProductMetricInteractionIdentity,
        result: AiChatProductMetricResult,
        sourceSurface: AiChatProductMetricSourceSurface,
    )
}

public struct AiChatProductMetricOperation: Equatable, Sendable {
    public let runID: AiChatRunID
    public let operationID: UUID

    public init(runID: AiChatRunID, operationID: UUID) {
        self.runID = runID
        self.operationID = operationID
    }
}

public struct AiChatProductMetricsClient: Sendable {
    public var record: @Sendable (AiChatProductMetric) -> Void

    public init(record: @escaping @Sendable (AiChatProductMetric) -> Void) {
        self.record = record
    }
}

extension AiChatProductMetricsClient: DependencyKey {
    public static let liveValue = AiChatProductMetricsClient { _ in }
    public static let testValue = AiChatProductMetricsClient { _ in }
}

public extension DependencyValues {
    var aiChatProductMetricsClient: AiChatProductMetricsClient {
        get { self[AiChatProductMetricsClient.self] }
        set { self[AiChatProductMetricsClient.self] = newValue }
    }
}

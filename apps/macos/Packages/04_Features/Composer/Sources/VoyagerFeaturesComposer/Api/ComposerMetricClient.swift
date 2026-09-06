import ComposableArchitecture
import Foundation

public enum ComposerMetricLevel: Sendable {
    case trace
    case debug
    case info
    case warn
    case error
}

public enum ComposerProductMetricResult: String, Sendable {
    case success
    case empty
    case failure
    case cancelled
}

public enum ComposerProductMetric: Sendable {
    case queryResult(operationID: UUID, result: ComposerProductMetricResult, durationMilliseconds: Int?)
    case applyResult(operationID: UUID, result: ComposerProductMetricResult, durationMilliseconds: Int?)
}

public struct ComposerMetricClient: Sendable {
    public var logMetric: @Sendable (
        _ name: String,
        _ value: Double,
        _ tags: [String: String]?,
        _ level: ComposerMetricLevel,
    ) -> Void
    public var recordProductMetric: @Sendable (ComposerProductMetric) -> Void

    public init(
        logMetric: @Sendable @escaping (
            String, Double, [String: String]?, ComposerMetricLevel,
        ) -> Void,
    ) {
        self.logMetric = logMetric
        recordProductMetric = { _ in }
    }

    public init(
        recordProductMetric: @escaping @Sendable (ComposerProductMetric) -> Void,
    ) {
        logMetric = { _, _, _, _ in }
        self.recordProductMetric = recordProductMetric
    }
}

extension ComposerMetricClient: DependencyKey {
    public static let liveValue = ComposerMetricClient { _, _, _, _ in }
    public static let testValue = ComposerMetricClient { _, _, _, _ in }
}

public extension DependencyValues {
    var composerMetricClient: ComposerMetricClient {
        get { self[ComposerMetricClient.self] }
        set { self[ComposerMetricClient.self] = newValue }
    }
}

public extension ComposerMetricClient {
    func record(_ metric: ComposerProductMetric) {
        recordProductMetric(metric)
    }

    func logMetric(
        _ name: String,
        value: Double,
        tags: [String: String]? = nil,
        level: ComposerMetricLevel = .info,
    ) {
        logMetric(name, value, tags, level)
    }
}

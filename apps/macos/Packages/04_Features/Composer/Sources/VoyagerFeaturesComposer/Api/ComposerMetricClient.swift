import ComposableArchitecture
import Foundation

public enum ComposerMetricLevel: Sendable {
    case trace
    case debug
    case info
    case warn
    case error
}

public struct ComposerMetricClient: Sendable {
    public var logMetric: @Sendable (
        _ name: String,
        _ value: Double,
        _ tags: [String: String]?,
        _ level: ComposerMetricLevel
    ) -> Void

    public init(
        logMetric: @Sendable @escaping (
            String, Double, [String: String]?, ComposerMetricLevel
        ) -> Void
    ) {
        self.logMetric = logMetric
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
    func logMetric(
        _ name: String,
        value: Double,
        tags: [String: String]? = nil,
        level: ComposerMetricLevel = .info
    ) {
        logMetric(name, value, tags, level)
    }
}

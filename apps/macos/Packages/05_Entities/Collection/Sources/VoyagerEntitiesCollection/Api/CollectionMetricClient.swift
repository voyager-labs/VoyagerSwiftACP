import ComposableArchitecture

public enum CollectionMetricLevel: String, Sendable {
    case trace
    case debug
    case info
    case warn
    case error
}

public struct CollectionMetricClient: Sendable {
    public var logMetric: @Sendable (
        _ name: String,
        _ value: Double,
        _ tags: [String: String],
        _ level: CollectionMetricLevel,
    ) -> Void

    public init(
        logMetric: @escaping @Sendable (
            _ name: String,
            _ value: Double,
            _ tags: [String: String],
            _ level: CollectionMetricLevel,
        ) -> Void,
    ) {
        self.logMetric = logMetric
    }
}

// swiftlint:disable modifier_order
extension CollectionMetricClient: DependencyKey {
    public nonisolated static let liveValue = CollectionMetricClient(
        logMetric: { _, _, _, _ in },
    )

    public nonisolated(unsafe) static var testValue = CollectionMetricClient(
        logMetric: { _, _, _, _ in },
    )
}

// swiftlint:enable modifier_order

public extension DependencyValues {
    nonisolated var collectionMetricClient: CollectionMetricClient {
        get { self[CollectionMetricClient.self] }
        set { self[CollectionMetricClient.self] = newValue }
    }
}

public extension CollectionMetricClient {
    func logMetric(
        _ name: String,
        value: Double = 1,
        tags: [String: String] = [:],
        level: CollectionMetricLevel = .info,
    ) {
        logMetric(name, value, tags, level)
    }
}

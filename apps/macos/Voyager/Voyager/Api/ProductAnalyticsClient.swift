import Foundation

public struct ProductAnalyticsClient: Sendable {
    public var captureMetricEvent: @Sendable (ProductAnalyticsMetricRequest) -> Void
    public var setDeviceIdentityEvent: @Sendable (String?) async -> Void
    public var deviceIdentityEvent: @Sendable () async -> String?

    nonisolated public init(
        captureMetric: @escaping @Sendable (ProductAnalyticsMetricRequest) -> Void = { _ in },
        setDeviceIdentity: @escaping @Sendable (String?) async -> Void = { _ in },
        deviceIdentity: @escaping @Sendable () async -> String? = { nil },
    ) {
        captureMetricEvent = captureMetric
        setDeviceIdentityEvent = setDeviceIdentity
        deviceIdentityEvent = deviceIdentity
    }

    nonisolated public static let disabled = ProductAnalyticsClient()

    nonisolated public func captureMetric(_ request: ProductAnalyticsMetricRequest) {
        captureMetricEvent(request)
    }

    public func setDeviceIdentity(_ deviceID: String?) async {
        await setDeviceIdentityEvent(deviceID)
    }

    public func deviceIdentity() async -> String? {
        await deviceIdentityEvent()
    }
}

public struct ProductAnalyticsMetricRequest: Equatable, Sendable {
    public let metricKey: String
    public let properties: [String: ProductAnalyticsPropertyValue]
    public let context: ProductAnalyticsEventContext
    public let eventVersion: ProductAnalyticsEventVersion
    public let operationID: UUID

    nonisolated public init(
        metricKey: String,
        properties: [String: ProductAnalyticsPropertyValue],
        context: ProductAnalyticsEventContext,
        eventVersion: ProductAnalyticsEventVersion = .init(rawValue: "1"),
        operationID: UUID = UUID(),
    ) {
        self.metricKey = metricKey
        self.properties = properties
        self.context = context
        self.eventVersion = eventVersion
        self.operationID = operationID
    }
}

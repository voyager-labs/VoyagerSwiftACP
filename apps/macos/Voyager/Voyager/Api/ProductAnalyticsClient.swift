import Foundation

public struct ProductAnalyticsClient: Sendable {
    public var captureEvent: @Sendable (ProductAnalyticsCaptureRequest) -> Void
    public var captureMetricEvent: @Sendable (ProductAnalyticsMetricRequest) -> Void
    public var setDeviceIdentityEvent: @Sendable (String?) async -> Void
    public var deviceIdentityEvent: @Sendable () async -> String?

    nonisolated public init(
        capture: @escaping @Sendable (ProductAnalyticsCaptureRequest) -> Void,
        captureMetric: @escaping @Sendable (ProductAnalyticsMetricRequest) -> Void = { _ in },
        setDeviceIdentity: @escaping @Sendable (String?) async -> Void = { _ in },
        deviceIdentity: @escaping @Sendable () async -> String? = { nil },
    ) {
        captureEvent = capture
        captureMetricEvent = captureMetric
        setDeviceIdentityEvent = setDeviceIdentity
        deviceIdentityEvent = deviceIdentity
    }

    nonisolated public static let disabled = ProductAnalyticsClient(capture: { _ in }, captureMetric: { _ in })

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

public protocol ProductAnalyticsClientProtocol: Sendable {
    func capture(_ request: ProductAnalyticsCaptureRequest)
}

extension ProductAnalyticsClient: ProductAnalyticsClientProtocol {
    public func capture(_ request: ProductAnalyticsCaptureRequest) {
        captureEvent(request)
    }
}

public struct ProductAnalyticsMetricRequest: Equatable, Sendable {
    public let metricKey: String
    public let properties: [String: ProductAnalyticsPropertyValue]
    public let context: ProductAnalyticsEventContext

    nonisolated public init(
        metricKey: String,
        properties: [String: ProductAnalyticsPropertyValue],
        context: ProductAnalyticsEventContext,
    ) {
        self.metricKey = metricKey
        self.properties = properties
        self.context = context
    }
}

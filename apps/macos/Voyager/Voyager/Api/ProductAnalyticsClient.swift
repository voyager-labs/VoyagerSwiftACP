import Foundation

public struct ProductAnalyticsClient: Sendable {
    public var captureEvent: @Sendable (ProductAnalyticsCaptureRequest) -> Void
    public var setDeviceIdentityEvent: @Sendable (String?) async -> Void
    public var deviceIdentityEvent: @Sendable () async -> String?

    nonisolated public init(
        capture: @escaping @Sendable (ProductAnalyticsCaptureRequest) -> Void,
        setDeviceIdentity: @escaping @Sendable (String?) async -> Void = { _ in },
        deviceIdentity: @escaping @Sendable () async -> String? = { nil },
    ) {
        captureEvent = capture
        setDeviceIdentityEvent = setDeviceIdentity
        deviceIdentityEvent = deviceIdentity
    }

    nonisolated public static let disabled = ProductAnalyticsClient(capture: { _ in })

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

import Foundation

public struct DeviceBindingRequest: Equatable, Sendable, Codable {
    public var deviceId: String
    public var deviceName: String?
    public var appVersion: String?
    public var osVersion: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }

    public init(
        deviceId: String,
        deviceName: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

public struct DeviceBindingResponse: Equatable, Sendable, Codable {
    public var ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

nonisolated public enum DeviceBindingError: Error, Equatable, Sendable {
    case unauthorized
    case noActiveAccess
    case seatCapacityExceeded
    case invalidDevicePayload
    case serverFailure
    case networkFailure
    case notConfigured
    case decodingFailure
    case unknownGatewayCode(String)
}

nonisolated public enum DeviceBindingFailure: Equatable, Sendable {
    case noActiveAccess
    case seatCapacityExceeded
    case retryable
    case invalidDevicePayload
    case unknown

    public var isRetryable: Bool {
        switch self {
        case .retryable, .invalidDevicePayload, .unknown:
            true
        case .noActiveAccess, .seatCapacityExceeded:
            false
        }
    }

    public var stepState: AccountAccessStepState {
        switch self {
        case .noActiveAccess, .seatCapacityExceeded:
            .blocked
        case .retryable, .invalidDevicePayload, .unknown:
            .error
        }
    }

    public var primaryCTA: AccessUnlockPrimaryCTA {
        switch self {
        case .noActiveAccess, .seatCapacityExceeded:
            .account
        case .retryable, .invalidDevicePayload, .unknown:
            .retry
        }
    }
}

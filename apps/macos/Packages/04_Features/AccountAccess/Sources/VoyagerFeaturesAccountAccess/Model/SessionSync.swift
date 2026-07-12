import Foundation

public enum SessionSyncIntent: String, Codable, Equatable, Sendable {
    case validate
    case refresh
}

public enum SessionSyncStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
}

public enum SessionSyncSessionStatus: String, Codable, Equatable, Sendable {
    case unchanged
    case rotated
}

public enum SessionSyncDeviceBindingOutcome: String, Codable, Equatable, Sendable {
    case bound
    case alreadyBound = "already_bound"
    case notAttempted = "not_attempted"
    case deviceLimitReached = "device_limit_reached"
}

public enum ConnectedDeviceAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct SessionSyncPartial: Codable, Equatable, Sendable {
    public var stage: String
    public var reason: String

    public init(stage: String, reason: String) {
        self.stage = stage
        self.reason = reason
    }
}

public struct SessionSyncResult: Equatable, Sendable {
    public var sessionStatus: SessionSyncSessionStatus
    public var syncStatus: SessionSyncStatus
    public var accessStatus: AccessStatusResponse
    public var deviceBindingOutcome: SessionSyncDeviceBindingOutcome
    public var connectedDeviceAvailability: ConnectedDeviceAvailability
    public var partial: SessionSyncPartial?
    public var sessionExpiresAt: Date?

    public init(
        sessionStatus: SessionSyncSessionStatus,
        syncStatus: SessionSyncStatus,
        accessStatus: AccessStatusResponse,
        deviceBindingOutcome: SessionSyncDeviceBindingOutcome,
        connectedDeviceAvailability: ConnectedDeviceAvailability,
        partial: SessionSyncPartial? = nil,
        sessionExpiresAt: Date? = nil,
    ) {
        self.sessionStatus = sessionStatus
        self.syncStatus = syncStatus
        self.accessStatus = accessStatus
        self.deviceBindingOutcome = deviceBindingOutcome
        self.connectedDeviceAvailability = connectedDeviceAvailability
        self.partial = partial
        self.sessionExpiresAt = sessionExpiresAt
    }
}

public enum SessionSyncError: Error, Equatable, Sendable {
    case invalidCredential
    case storageFailure
    case upstream(Int)
    case capabilityMiss
}

struct SessionSyncRequest: Codable {
    var mode: SessionSyncIntent
    var requestID: String
    var deviceID: String
    var deviceName: String?
    var appVersion: String?
    var osVersion: String?
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case requestID = "request_id"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case refreshToken = "refresh_token"
    }
}

struct SessionSyncResponse: Codable {
    var syncStatus: SessionSyncStatus
    var session: Session
    var access: AccessStatusResponse
    var device: Device
    var partial: SessionSyncPartial?

    struct Session: Codable {
        var status: SessionSyncSessionStatus
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Int64?
        var expiresIn: Int64?
        var refreshTokenExpiresAt: Int64?

        enum CodingKeys: String, CodingKey {
            case status
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case expiresIn = "expires_in"
            case refreshTokenExpiresAt = "refresh_token_expires_at"
        }
    }

    struct Device: Codable {
        var outcome: SessionSyncDeviceBindingOutcome
        var connectedDeviceAvailability: ConnectedDeviceAvailability

        enum CodingKeys: String, CodingKey {
            case outcome
            case connectedDeviceAvailability = "connected_device_availability"
        }
    }

    func result() -> SessionSyncResult {
        SessionSyncResult(
            sessionStatus: session.status,
            syncStatus: syncStatus,
            accessStatus: access,
            deviceBindingOutcome: device.outcome,
            connectedDeviceAvailability: device.connectedDeviceAvailability,
            partial: partial,
            sessionExpiresAt: session.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
        )
    }
}

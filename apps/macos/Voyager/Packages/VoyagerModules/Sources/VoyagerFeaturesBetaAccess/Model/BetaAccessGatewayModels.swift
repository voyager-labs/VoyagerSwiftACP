import Foundation

public struct BetaAccessVerifyRequest: Encodable, Sendable {
    public let email: String
    public let deviceId: String
    public let appVersion: String?
    public let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case email
        case deviceId = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }

    public init(email: String, deviceId: String, appVersion: String?, osVersion: String?) {
        self.email = email
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

public struct BetaAccessVerifyResponse: Decodable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

public struct BetaAccessErrorResponse: Decodable, Sendable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

public enum BetaAccessVerificationError: Error, Equatable, Sendable {
    case invalidRequest
    case deviceIdUnavailable
    case networkError
    case decodingError
    case gatewayError(code: String)
}

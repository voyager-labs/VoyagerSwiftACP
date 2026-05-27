import Foundation

public struct AccessClaimRequest: Encodable, Sendable {
    public let mode: AccessClaimMode
    public let value: String
    public let deviceId: String?
    public let appVersion: String?
    public let osVersion: String?
    enum CodingKeys: String, CodingKey {
        case mode, value
        case deviceId = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }

    public init(
        mode: AccessClaimMode,
        value: String,
        deviceId: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
    ) {
        self.mode = mode
        self.value = value
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

import Foundation

struct BetaAccessVerifyRequest: Encodable, Sendable {
    let email: String
    let deviceId: String
    let appVersion: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case email
        case deviceId = "device_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }
}

struct BetaAccessVerifyResponse: Decodable, Sendable {
    let ok: Bool
}

struct BetaAccessErrorResponse: Decodable, Sendable {
    let error: String
}

enum BetaAccessVerificationError: Error, Equatable, Sendable {
    case invalidRequest
    case deviceIdUnavailable
    case networkError
    case decodingError
    case gatewayError(code: String)
}

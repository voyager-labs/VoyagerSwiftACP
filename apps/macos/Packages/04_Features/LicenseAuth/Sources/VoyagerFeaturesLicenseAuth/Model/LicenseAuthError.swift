import Foundation

public nonisolated enum LicenseAuthError: Error, Equatable, Sendable {
    case networkFailure
    case notConfigured
    case decodingFailure
    case unknownGatewayCode(String)
}

import Foundation

public nonisolated enum AccessError: Error, Equatable, Sendable {
    case missingInput
    case invalidLicenseKey
    case licenseAlreadyUsed
    case licenseRevoked
    case licenseRefunded
    case betaCodeAlreadyRedeemed
    case betaCodeExpired
    case networkFailure
    case notConfigured
    case decodingFailure
    case unknownGatewayCode(String)
}

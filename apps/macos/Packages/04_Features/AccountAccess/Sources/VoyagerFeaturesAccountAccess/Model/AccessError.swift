import Foundation

public nonisolated enum AccessError: Error, Equatable, Sendable {
    case networkFailure
    case notConfigured
    case decodingFailure
    case unknownGatewayCode(String)
}

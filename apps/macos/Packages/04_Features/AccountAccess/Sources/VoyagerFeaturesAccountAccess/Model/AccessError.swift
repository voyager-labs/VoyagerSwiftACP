import Foundation

nonisolated public enum AccessError: Error, Equatable, Sendable {
    case networkFailure
    case notConfigured
    case decodingFailure
    case unauthorized
    case unknownGatewayCode(String)
}

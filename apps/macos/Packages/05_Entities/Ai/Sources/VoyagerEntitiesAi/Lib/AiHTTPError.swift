import Foundation

public enum AiHTTPError: Error, Sendable, Equatable {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String)
    case networkError(String)
    case timeout
    case cancelled
}

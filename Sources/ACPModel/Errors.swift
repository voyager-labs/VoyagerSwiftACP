import Foundation

/// Typed failure taxonomy for transport-level problems. Values carry metadata
/// (byte counts, categories) and never carry wire payload content.
public enum TransportFailure: Error, Sendable, Equatable {
    case startup(String)
    case read(String)
    case write(String)
    /// The frame could not be interpreted; the associated string is a fixed,
    /// payload-free reason such as "frame is not a JSON object".
    case malformedFrame(String)
    case frameLimit(Int)
    case bufferOverflow(Int)
    case shutdownTimeout
}

public enum ClientError: Error, LocalizedError, Sendable {
    case processNotRunning
    case processFailed(Int32)
    case invalidResponse
    case requestTimeout
    case encodingError
    case decodingError(Error)
    case agentError(JSONRPCError)
    case delegateNotSet
    case fileNotFound(String)
    case fileOperationFailed(String)
    case transportError(String)
    case connectionClosed
    case notConnected
    case notInitialized
    case initializationInProgress
    case alreadyInitialized
    case initializationFailed(String)
    case unsupportedProtocolVersion(Int)
    case unsupportedCapability(String)
    case unknownSession(SessionId)
    case sessionBusy(SessionId)
    case sessionClosed(SessionId)
    case protocolViolation(String)
    case unknownMethod(String)
    case invalidParams(String)
    case requestIDExhausted
    case transportFailure(TransportFailure)

    public var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "Agent process is not running"
        case let .processFailed(code):
            return "Agent process failed with exit code \(code)"
        case .invalidResponse:
            return "Invalid response from agent"
        case .requestTimeout:
            return "Request timed out"
        case .encodingError:
            return "Failed to encode request"
        case let .decodingError(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case let .agentError(jsonError):
            if let dataString = jsonError.data?.value as? String {
                return dataString
            }

            if let data = jsonError.data?.value as? [String: Any],
               let details = data["details"] as? String
            {
                if let detailsData = details.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: detailsData) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String
                {
                    return message
                }
                return details
            }

            return jsonError.message
        case .delegateNotSet:
            return "Internal error: Delegate not set"
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .fileOperationFailed(message):
            return "File operation failed: \(message)"
        case let .transportError(message):
            return "Transport error: \(message)"
        case .connectionClosed:
            return "Connection closed"
        case .notConnected:
            return "Transport is not connected; call start() or launch() first"
        case .notInitialized:
            return "Session is not initialized; call initialize() before other operations"
        case .initializationInProgress:
            return "Initialization is already in progress"
        case .alreadyInitialized:
            return "Connection is already initialized"
        case let .initializationFailed(reason):
            return "Initialization failed; the connection is terminal: \(reason)"
        case let .unsupportedProtocolVersion(version):
            return "Agent selected unsupported protocol version \(version)"
        case let .unsupportedCapability(capability):
            return "Agent does not advertise the \(capability) capability"
        case let .unknownSession(sessionId):
            return "Unknown session: \(sessionId.value)"
        case let .sessionBusy(sessionId):
            return "Session \(sessionId.value) already has an active prompt"
        case let .sessionClosed(sessionId):
            return "Session \(sessionId.value) is closed"
        case let .protocolViolation(reason):
            return "Protocol violation: \(reason)"
        case let .unknownMethod(method):
            return "Method not found: \(method)"
        case let .invalidParams(reason):
            return "Invalid params: \(reason)"
        case .requestIDExhausted:
            return "Request ID space is exhausted"
        case let .transportFailure(failure):
            return "Transport failure: \(failure)"
        }
    }
}

// MARK: - Typealiases for backward compatibility

@available(*, deprecated, renamed: "ClientError")
public typealias ACPClientError = ClientError

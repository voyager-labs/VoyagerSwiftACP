import ACPModel
import Foundation

/// Routes inbound agent→client requests and notifications to the delegate.
///
/// The router is a plain lock-protected class (not an actor) so that
/// `Client.setDelegate` installs the delegate synchronously: callbacks that
/// arrive before or during initialization can never race the installation.
/// The lock protects only the delegate reference; routing awaits the delegate's
/// async methods outside the lock.
final class ACPRequestRouter: @unchecked Sendable {
    // MARK: - Properties

    private let lock = NSLock()
    private weak var _delegate: ClientDelegate?

    // MARK: - Delegate Management

    weak var delegate: ClientDelegate? {
        lock.lock()
        defer { lock.unlock() }
        return _delegate
    }

    func setDelegate(_ delegate: ClientDelegate?) {
        lock.lock()
        _delegate = delegate
        lock.unlock()
    }

    // MARK: - Request Routing

    func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        switch request.method {
        case "fs/read_text_file":
            return try await handleFileRead(request)
        case "fs/write_text_file":
            return try await handleFileWrite(request)
        case "terminal/create":
            return try await handleTerminalCreateRequest(request)
        case "terminal/output":
            return try await handleTerminalOutputRequest(request)
        case "terminal/wait_for_exit":
            return try await handleTerminalWaitForExitRequest(request)
        case "terminal/kill":
            return try await handleTerminalKill(request)
        case "terminal/release":
            return try await handleTerminalRelease(request)
        case "request_permission", "session/request_permission":
            return try await handlePermissionRequestMethod(request)
        case "mcp/connect":
            return try await handleMcpConnect(request)
        case "mcp/message":
            return try await handleMcpMessage(request)
        case "mcp/disconnect":
            return try await handleMcpDisconnect(request)
        case "elicitation/create":
            return try await handleCreateElicitation(request)
        default:
            // Unknown method: the connection stays open; the caller answers -32601.
            throw ClientError.unknownMethod(request.method)
        }
    }

    func routeNotification(_ notification: JSONRPCNotification) async throws {
        guard let delegate else { return }

        switch notification.method {
        case "mcp/message":
            let notification = try decodeParams(MessageMcpNotification.self, from: notification.params)
            try await delegate.handleMcpNotification(notification)

        case "elicitation/complete":
            let notification = try decodeParams(CompleteElicitationNotification.self, from: notification.params)
            try await delegate.handleCompleteElicitation(notification)

        default:
            return
        }
    }

    // MARK: - Param Decoding

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params, !(params.value is NSNull) else {
            throw ClientError.invalidParams("missing params")
        }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(params)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ClientError.invalidParams("params could not be decoded")
        }
    }

    // MARK: - Request Handlers

    private func handleFileRead(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(ReadTextFileRequest.self, from: request.params)

        let response = try await delegate.handleFileReadRequest(
            req.path,
            sessionId: req.sessionId,
            line: req.line,
            limit: req.limit,
        )

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleFileWrite(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(WriteTextFileRequest.self, from: request.params)

        let response = try await delegate.handleFileWriteRequest(
            req.path,
            content: req.content,
            sessionId: req.sessionId,
        )

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalCreateRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(CreateTerminalRequest.self, from: request.params)

        let response = try await delegate.handleTerminalCreate(
            command: req.command,
            sessionId: req.sessionId,
            args: req.args,
            cwd: req.cwd,
            env: req.env,
            outputByteLimit: req.outputByteLimit,
        )

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalOutputRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(TerminalOutputRequest.self, from: request.params)

        let response = try await delegate.handleTerminalOutput(terminalId: req.terminalId, sessionId: req.sessionId)

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalWaitForExitRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(WaitForExitRequest.self, from: request.params)

        let response = try await delegate.handleTerminalWaitForExit(
            terminalId: req.terminalId,
            sessionId: req.sessionId,
        )

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalKill(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(KillTerminalRequest.self, from: request.params)

        let response = try await delegate.handleTerminalKill(terminalId: req.terminalId, sessionId: req.sessionId)

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalRelease(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(ReleaseTerminalRequest.self, from: request.params)

        let response = try await delegate.handleTerminalRelease(terminalId: req.terminalId, sessionId: req.sessionId)

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handlePermissionRequestMethod(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(RequestPermissionRequest.self, from: request.params)

        let response = try await delegate.handlePermissionRequest(request: req)

        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleMcpConnect(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(ConnectMcpRequest.self, from: request.params)
        let response = try await delegate.handleMcpConnect(req)
        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleMcpMessage(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(MessageMcpRequest.self, from: request.params)
        return try await delegate.handleMcpMessage(req)
    }

    private func handleMcpDisconnect(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(DisconnectMcpRequest.self, from: request.params)
        let response = try await delegate.handleMcpDisconnect(req)
        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }

    private func handleCreateElicitation(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        let req = try decodeParams(CreateElicitationRequest.self, from: request.params)
        let response = try await delegate.handleCreateElicitation(req)
        let responseData = try JSONEncoder().encode(response)
        return try JSONDecoder().decode(AnyCodable.self, from: responseData)
    }
}

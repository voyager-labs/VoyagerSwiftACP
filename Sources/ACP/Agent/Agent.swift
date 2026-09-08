import ACPModel
import Foundation
import os.log

/// Incoming request from a client that the agent must handle
public struct AgentRequest: Sendable {
    public let id: RequestId
    public let method: String
    public let params: AnyCodable?

    public init(id: RequestId, method: String, params: AnyCodable?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Agent runtime that receives requests from clients and sends responses/updates
public actor Agent {
    // MARK: - Properties

    private let transport: any Transport
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private weak var delegate: AgentDelegate?
    private var pendingRequests = PendingRequestTable<JSONRPCResponse>()
    private var nextRequestID = 1

    private var requestContinuation: AsyncStream<AgentRequest>.Continuation?
    private let requestStream: AsyncStream<AgentRequest>

    private struct InboundContext {
        var task: Task<Void, Never>?
    }

    private var inboundRequests: [RequestId: InboundContext] = [:]
    private var isClosed = false

    /// Session work is only legal after a successful `initialize` handshake
    /// (protocol version and capabilities negotiated); peer requests that skip
    /// it are refused locally instead of reaching the delegate.
    private enum InitializationPhase {
        case awaitingInitialize
        case initializing
        case initialized
    }

    private var initializationPhase: InitializationPhase = .awaitingInitialize

    // MARK: - Public API

    /// Stream of incoming requests from the client (methods without a built-in
    /// delegate route).
    nonisolated public var requests: AsyncStream<AgentRequest> {
        requestStream
    }

    // MARK: - Initialization

    public init(transport: any Transport) {
        self.transport = transport
        logger = Logger.forCategory("Agent")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        decoder = JSONDecoder()

        var continuation: AsyncStream<AgentRequest>.Continuation!
        requestStream = AsyncStream { cont in
            continuation = cont
        }
        requestContinuation = continuation
    }

    public func setDelegate(_ delegate: AgentDelegate?) {
        self.delegate = delegate
    }

    /// Start processing incoming messages from the transport. Returns when the
    /// transport's message stream ends.
    public func start() async {
        for await frame in transport.messages {
            await ingest(frame)
        }
        await ingressDidEnd()
    }

    /// Send a session update notification to the client
    public func sendUpdate(sessionId: SessionId, update: SessionUpdate) async throws {
        let notification = SessionUpdateNotification(sessionId: sessionId, update: update)
        let paramsData = try encoder.encode(notification)
        let params = try decoder.decode(AnyCodable.self, from: paramsData)

        let message = JSONRPCNotification(method: "session/update", params: params)
        let data = try encoder.encode(message)
        try await transport.send(data)
    }

    /// Send an agent message chunk update
    public func sendMessageChunk(sessionId: SessionId, text: String) async throws {
        let content = ContentBlock.text(TextContent(text: text))
        let update = SessionUpdate.agentMessageChunk(content)
        try await sendUpdate(sessionId: sessionId, update: update)
    }

    /// Send a tool call update
    public func sendToolCall(sessionId: SessionId, toolCall: ToolCallUpdate) async throws {
        let update = SessionUpdate.toolCall(toolCall)
        try await sendUpdate(sessionId: sessionId, update: update)
    }

    /// Send a session metadata update notification
    public func sendSessionInfoUpdate(sessionId: SessionId, info: SessionInfoUpdate) async throws {
        try await sendUpdate(sessionId: sessionId, update: .sessionInfoUpdate(info))
    }

    /// Send a session usage update notification
    public func sendUsageUpdate(sessionId: SessionId, usage: UsageUpdate) async throws {
        try await sendUpdate(sessionId: sessionId, update: .usageUpdate(usage))
    }

    /// Request an MCP-over-ACP connection from the client.
    public func connectMcp(serverId: McpServerAcpId) async throws -> ConnectMcpResponse {
        let request = ConnectMcpRequest(serverId: serverId)
        let response = try await sendRequest(method: "mcp/connect", params: request)
        return try decodeResponse(ConnectMcpResponse.self, from: response)
    }

    /// Send an MCP-over-ACP request message to the client.
    public func sendMcpMessage(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil,
    ) async throws -> MessageMcpResponse {
        let request = MessageMcpRequest(connectionId: connectionId, method: method, params: params)
        let response = try await sendRequest(method: "mcp/message", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        return result
    }

    /// Send an MCP-over-ACP notification message to the client.
    public func sendMcpMessageNotification(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil,
    ) async throws {
        try await sendNotification(
            method: "mcp/message",
            params: MessageMcpNotification(connectionId: connectionId, method: method, params: params),
        )
    }

    /// Disconnect an MCP-over-ACP connection on the client.
    public func disconnectMcp(connectionId: McpConnectionId) async throws -> DisconnectMcpResponse {
        let request = DisconnectMcpRequest(connectionId: connectionId)
        let response = try await sendRequest(method: "mcp/disconnect", params: request)
        return try decodeEmptyTolerantResponse(
            DisconnectMcpResponse.self,
            from: response,
            emptyValue: DisconnectMcpResponse(),
        )
    }

    /// Request structured user input from the client.
    public func createElicitation(_ request: CreateElicitationRequest) async throws -> CreateElicitationResponse {
        let response = try await sendRequest(method: "elicitation/create", params: request)
        return try decodeResponse(CreateElicitationResponse.self, from: response)
    }

    /// Notify the client that a URL-based elicitation completed.
    public func completeElicitation(elicitationId: ElicitationId) async throws {
        try await sendNotification(
            method: "elicitation/complete",
            params: CompleteElicitationNotification(elicitationId: elicitationId),
        )
    }

    /// Close the agent and fail every outbound pending request exactly once.
    public func close() async {
        await close(failure: ClientError.connectionClosed)
    }

    private func close(failure: ClientError) async {
        guard !isClosed else { return }
        isClosed = true

        await transport.close()
        pendingRequests.failAll(failure)
        cancelInboundTasks()
        requestContinuation?.finish()
    }

    // MARK: - Ingress

    private func ingest(_ frame: Data) async {
        guard !isClosed else { return }

        let message: Message
        do {
            message = try decoder.decode(Message.self, from: frame)
        } catch {
            guard (try? decoder.decode(AnyCodable.self, from: frame)) != nil else {
                try? await sendErrorResponse(id: .null, code: -32700, message: "Parse error")
                await close(failure: .protocolViolation("malformed JSON"))
                return
            }
            // A well-framed but structurally invalid envelope: answer -32600,
            // echoing the id when it is recoverable as a valid RequestId, and
            // keep the connection.
            try? await sendErrorResponse(
                id: Self.recoverRequestID(from: frame) ?? .null,
                code: -32600,
                message: "Invalid Request",
            )
            return
        }

        switch message {
        case let .request(request):
            dispatchInbound(request)
        case let .notification(notification):
            await handleNotification(notification)
        case let .response(response):
            handleResponse(response)
        }
    }

    private func ingressDidEnd() async {
        let evidence = await transport.termination

        if !isClosed {
            if case .failure(.malformedFrame) = evidence?.reason {
                // The peer sent a frame we could not parse; respond with a
                // best-effort parse error before terminating the connection.
                try? await sendErrorResponse(id: .null, code: -32700, message: "Parse error")
            }
            isClosed = true
            await transport.close()
        }

        pendingRequests.failAll(ClientError.connectionClosed)
        cancelInboundTasks()
        requestContinuation?.finish()
    }

    /// Best-effort id recovery from a raw frame whose envelope otherwise failed
    /// to decode.
    private static func recoverRequestID(from frame: Data) -> RequestId? {
        struct EnvelopeID: Decodable {
            let id: RequestId
        }
        return try? JSONDecoder().decode(EnvelopeID.self, from: frame).id
    }

    private func dispatchInbound(_ request: JSONRPCRequest) {
        var context = InboundContext()
        let task = Task { [weak self] () in
            guard let self else { return }
            await processInbound(request)
        }
        context.task = task
        inboundRequests[request.id] = context
    }

    private func processInbound(_ request: JSONRPCRequest) async {
        do {
            let result = try await routeRequest(request)
            try await sendResponseIfOpen(id: request.id, result: result)
        } catch {
            if error is CancellationError, request.method == "session/prompt" {
                // A cancelled prompt turn ends with a cancelled stop reason.
                let cancelled = SessionPromptResponse(stopReason: .cancelled)
                if let data = try? encoder.encode(cancelled),
                   let result = try? decoder.decode(AnyCodable.self, from: data)
                {
                    try? await sendResponseIfOpen(id: request.id, result: result)
                    await finishInbound(request.id)
                    return
                }
            }
            let payload = Self.errorPayload(from: error)
            try? await sendErrorResponseIfOpen(
                id: request.id, code: payload.code, message: payload.message, data: payload.data,
            )
        }
        await finishInbound(request.id)
    }

    private func finishInbound(_ id: RequestId) async {
        inboundRequests.removeValue(forKey: id)
    }

    private func sendResponseIfOpen(id: RequestId, result: AnyCodable) async throws {
        guard inboundRequests[id] != nil, !isClosed else { return }
        let response = JSONRPCResponse(id: id, result: result, error: nil)
        let data = try encoder.encode(response)
        try await transport.send(data)
    }

    private func sendErrorResponseIfOpen(id: RequestId, code: Int, message: String, data: AnyCodable?) async throws {
        guard inboundRequests[id] != nil, !isClosed else { return }
        try await sendErrorResponse(id: id, code: code, message: message, data: data)
    }

    private func cancelInboundTasks() {
        for (_, context) in inboundRequests {
            context.task?.cancel()
        }
        inboundRequests.removeAll()
    }

    /// Maps handler failures to JSON-RPC error payloads. A delegate's explicit
    /// `JSONRPCError` preserves code/message/data; everything else collapses to a
    /// fixed, payload-free internal error message.
    private static func errorPayload(from error: Error) -> JSONRPCError {
        if let jsonError = error as? JSONRPCError {
            return jsonError
        }
        if let clientError = error as? ClientError {
            switch clientError {
            case let .unknownMethod(method):
                return JSONRPCError(code: -32601, message: "Method not found", data: AnyCodable(["method": method]))
            case .invalidParams:
                return JSONRPCError(code: -32602, message: "Invalid params", data: nil)
            case .notInitialized:
                return JSONRPCError(code: -32002, message: "Not initialized", data: nil)
            case .alreadyInitialized, .initializationInProgress:
                return JSONRPCError(code: -32600, message: "Initialize already in progress or completed", data: nil)
            default:
                break
            }
        }
        if error is DecodingError {
            return JSONRPCError(code: -32602, message: "Invalid params", data: nil)
        }
        return JSONRPCError(code: -32603, message: "Internal error", data: nil)
    }

    // MARK: - Outbound Requests

    private func handleResponse(_ response: JSONRPCResponse) {
        guard pendingRequests.contains(response.id) else {
            logger.debug("Ignoring response for unknown request id")
            return
        }
        pendingRequests.complete(id: response.id, .success(response))
    }

    private func sendRequest(method: String, params: some Encodable) async throws -> JSONRPCResponse {
        guard !isClosed else {
            throw ClientError.connectionClosed
        }
        let requestID = nextRequestID
        guard requestID > 0, requestID < Int.max else {
            throw ClientError.requestIDExhausted
        }
        nextRequestID += 1
        let requestIdentifier = RequestId.number(requestID)

        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let request = JSONRPCRequest(
            id: requestIdentifier,
            method: method,
            params: paramsValue,
        )

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCResponse, Error>) in
                // Actor-isolated body: registration happens before suspension.
                pendingRequests.register(id: requestIdentifier, continuation: continuation)
                let writeTask = Task { [weak self] () in
                    guard let self else { return }
                    await performWrite(id: requestIdentifier, request: request)
                }
                pendingRequests.attachWriteTask(id: requestIdentifier, task: writeTask)
            }
        }, onCancel: { [weak self] in
            Task { await self?.callerCancelled(requestID: requestID) }
        })
    }

    private func callerCancelled(requestID: Int) {
        pendingRequests.complete(id: .number(requestID), .failure(CancellationError()))
    }

    private func performWrite(id: RequestId, request: JSONRPCRequest) async {
        guard !Task.isCancelled else { return }
        do {
            let data = try encoder.encode(request)
            try await transport.send(data)
        } catch {
            if pendingRequests.contains(id) {
                pendingRequests.complete(id: id, .failure(ClientError.transportFailure(.write("request write failed"))))
            }
        }
    }

    private func sendNotification(method: String, params: some Encodable) async throws {
        let paramsData = try encoder.encode(params)
        let paramsValue = try decoder.decode(AnyCodable.self, from: paramsData)

        let notification = JSONRPCNotification(
            method: method,
            params: paramsValue,
        )
        let data = try encoder.encode(notification)
        try await transport.send(data)
    }

    private func sendResponse(id: RequestId, result: AnyCodable) async throws {
        let response = JSONRPCResponse(id: id, result: result, error: nil)
        let data = try encoder.encode(response)
        try await transport.send(data)
    }

    private func sendErrorResponse(id: RequestId, code: Int, message: String, data: AnyCodable? = nil) async throws {
        let error = JSONRPCError(code: code, message: message, data: data)
        let response = JSONRPCResponse(id: id, result: nil, error: error)
        let encoded = try encoder.encode(response)
        try await transport.send(encoded)
    }

    // MARK: - Decoding Helpers

    private func decodeResponse<T: Decodable>(_ type: T.Type, from response: JSONRPCResponse) throws -> T {
        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result, !(result.value is NSNull) else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    private func decodeEmptyTolerantResponse<T: Decodable>(
        _ type: T.Type,
        from response: JSONRPCResponse,
        emptyValue: @autoclosure () -> T,
    ) throws -> T {
        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return emptyValue()
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return emptyValue()
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(type, from: data)
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params, !(params.value is NSNull) else {
            throw ClientError.invalidParams("missing params")
        }
        let data = try encoder.encode(params)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ClientError.invalidParams("params could not be decoded")
        }
    }

    private func decodeParamsIfPresent<T: Decodable>(_ type: T.Type, from params: AnyCodable?) throws -> T {
        guard let params, !(params.value is NSNull) else {
            return try decoder.decode(type, from: Data("{}".utf8))
        }
        let data = try encoder.encode(params)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ClientError.invalidParams("params could not be decoded")
        }
    }

    private func encodeResult(_ result: some Encodable) throws -> AnyCodable {
        let data = try encoder.encode(result)
        return try decoder.decode(AnyCodable.self, from: data)
    }
}

/// Inbound dispatch shares the Agent actor isolation and private state.
extension Agent {
    // MARK: - Routing

    private func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate else {
            throw ClientError.delegateNotSet
        }

        switch request.method {
        case "initialize":
            return try await handleInitializeRequest(request, delegate: delegate)

        case "session/new":
            try requireInitialized()
            let params = try decodeParams(NewSessionRequest.self, from: request.params)
            let response = try await delegate.handleNewSession(params)
            return try encodeResult(response)

        case "session/prompt":
            try requireInitialized()
            let params = try decodeParams(SessionPromptRequest.self, from: request.params)
            let response = try await delegate.handlePrompt(params)
            return try encodeResult(response)

        case "session/load":
            try requireInitialized()
            let params = try decodeParams(LoadSessionRequest.self, from: request.params)
            let response = try await delegate.handleLoadSession(params)
            return try encodeResult(response)

        case "session/resume":
            try requireInitialized()
            let params = try decodeParams(ResumeSessionRequest.self, from: request.params)
            let response = try await delegate.handleResumeSession(params)
            return try encodeResult(response)

        case "session/fork":
            try requireInitialized()
            let params = try decodeParams(ForkSessionRequest.self, from: request.params)
            let response = try await delegate.handleForkSession(params)
            return try encodeResult(response)

        case "session/list":
            try requireInitialized()
            let params = try decodeParams(ListSessionsRequest.self, from: request.params)
            let response = try await delegate.handleListSessions(params)
            return try encodeResult(response)

        case "session/close":
            try requireInitialized()
            let params = try decodeParams(CloseSessionRequest.self, from: request.params)
            try await delegate.handleCancel(params.sessionId)
            let response = try await delegate.handleCloseSession(params)
            return try encodeResult(response)

        default:
            return try await routeExtensionRequest(request, delegate: delegate)
        }
    }

    private func requireInitialized() throws {
        guard initializationPhase == .initialized else {
            throw ClientError.notInitialized
        }
    }

    /// Runs the one-time initialize handshake. A concurrent handshake and a
    /// second completed handshake are refused; a failed one stays retryable.
    private func handleInitializeRequest(
        _ request: JSONRPCRequest,
        delegate: any AgentDelegate,
    ) async throws -> AnyCodable {
        switch initializationPhase {
        case .initializing:
            throw ClientError.initializationInProgress
        case .initialized:
            throw ClientError.alreadyInitialized
        case .awaitingInitialize:
            break
        }
        let params = try decodeParams(InitializeRequest.self, from: request.params)
        initializationPhase = .initializing
        do {
            let response = try await delegate.handleInitialize(params)
            initializationPhase = .initialized
            return try encodeResult(InitializeResponse(
                protocolVersion: 1,
                agentCapabilities: response.agentCapabilities,
                agentInfo: response.agentInfo,
                authMethods: response.authMethods,
                _meta: response._meta,
            ))
        } catch {
            initializationPhase = .awaitingInitialize
            throw error
        }
    }

    /// Session-scoped extensions drive external work, so they wait for the
    /// handshake like core session requests. Pure routing extensions (logout,
    /// providers/*) and unknown methods keep their documented pre-initialize
    /// behavior.
    private func requireInitializedForExtension(_ method: String) throws {
        switch method {
        case "session/delete", "nes/start", "nes/suggest", "nes/close", "mcp/message":
            try requireInitialized()
        default:
            break
        }
    }

    private func routeExtensionRequest(
        _ request: JSONRPCRequest,
        delegate: any AgentDelegate,
    ) async throws -> AnyCodable {
        try requireInitializedForExtension(request.method)

        switch request.method {
        case "session/delete":
            let params = try decodeParams(DeleteSessionRequest.self, from: request.params)
            let response = try await delegate.handleDeleteSession(params)
            return try encodeResult(response)

        case "logout":
            let params = try decodeParamsIfPresent(LogoutRequest.self, from: request.params)
            let response = try await delegate.handleLogout(params)
            return try encodeResult(response)

        case "providers/list":
            let params = try decodeParamsIfPresent(ListProvidersRequest.self, from: request.params)
            let response = try await delegate.handleListProviders(params)
            return try encodeResult(response)

        case "providers/set":
            let params = try decodeParams(SetProviderRequest.self, from: request.params)
            let response = try await delegate.handleSetProvider(params)
            return try encodeResult(response)

        case "providers/disable":
            let params = try decodeParams(DisableProviderRequest.self, from: request.params)
            let response = try await delegate.handleDisableProvider(params)
            return try encodeResult(response)

        case "nes/start":
            let params = try decodeParamsIfPresent(StartNesRequest.self, from: request.params)
            let response = try await delegate.handleStartNes(params)
            return try encodeResult(response)

        case "nes/suggest":
            let params = try decodeParams(SuggestNesRequest.self, from: request.params)
            let response = try await delegate.handleSuggestNes(params)
            return try encodeResult(response)

        case "nes/close":
            let params = try decodeParams(CloseNesRequest.self, from: request.params)
            let response = try await delegate.handleCloseNes(params)
            return try encodeResult(response)

        case "mcp/message":
            let params = try decodeParams(MessageMcpRequest.self, from: request.params)
            return try await delegate.handleMcpMessage(params)

        default:
            // Emit to request stream for custom handling; the wire answer is -32601.
            requestContinuation?.yield(AgentRequest(
                id: request.id,
                method: request.method,
                params: request.params,
            ))
            throw ClientError.unknownMethod(request.method)
        }
    }

    private func handleNotification(_ notification: JSONRPCNotification) async {
        do {
            try await routeNotification(notification)
        } catch {
            await close(failure: .protocolViolation("invalid notification params"))
        }
    }

    private func routeNotification(_ notification: JSONRPCNotification) async throws {
        // Cancellation must stay receivable during any phase (including a
        // prompt turn); every other notification assumes a negotiated session.
        switch notification.method {
        case "session/cancel", "$/cancel_request":
            break
        default:
            try requireInitialized()
        }

        switch notification.method {
        case "session/cancel":
            let request = try decodeParams(CancelSessionRequest.self, from: notification.params)
            try? await delegate?.handleCancel(request.sessionId)
        case "$/cancel_request":
            let request = try decodeParams(CancelRequestNotification.self, from: notification.params)
            try? await delegate?.handleCancelRequest(request)
        case "nes/accept":
            let request = try decodeParams(AcceptNesNotification.self, from: notification.params)
            try? await delegate?.handleAcceptNes(request)
        case "nes/reject":
            let request = try decodeParams(RejectNesNotification.self, from: notification.params)
            try? await delegate?.handleRejectNes(request)
        case "mcp/message":
            let request = try decodeParams(MessageMcpNotification.self, from: notification.params)
            try? await delegate?.handleMcpNotification(request)
        default:
            try await routeDocumentNotification(notification)
        }
    }

    private func routeDocumentNotification(_ notification: JSONRPCNotification) async throws {
        switch notification.method {
        case "document/didOpen":
            let request = try decodeParams(DidOpenDocumentNotification.self, from: notification.params)
            try? await delegate?.handleDidOpenDocument(request)
        case "document/didChange":
            let request = try decodeParams(DidChangeDocumentNotification.self, from: notification.params)
            try? await delegate?.handleDidChangeDocument(request)
        case "document/didClose":
            let request = try decodeParams(DidCloseDocumentNotification.self, from: notification.params)
            try? await delegate?.handleDidCloseDocument(request)
        case "document/didSave":
            let request = try decodeParams(DidSaveDocumentNotification.self, from: notification.params)
            try? await delegate?.handleDidSaveDocument(request)
        case "document/didFocus":
            let request = try decodeParams(DidFocusDocumentNotification.self, from: notification.params)
            try? await delegate?.handleDidFocusDocument(request)
        default:
            logger.debug("Unhandled notification method class")
        }
    }
}

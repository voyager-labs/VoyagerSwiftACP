@testable import ACP
import ACPModel
import Foundation

actor RecordingAgentDelegate: AgentDelegate {
    private(set) var events: [String] = []
    private var promptStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var promptSuspension: CheckedContinuation<SessionPromptResponse, Error>?
    private var holdNextPrompt = false

    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse {
        events.append("initialize:\(request.protocolVersion)")
        return InitializeResponse(protocolVersion: 1, agentCapabilities: AgentCapabilities())
    }

    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse {
        events.append("new:\(request.cwd)")
        return NewSessionResponse(sessionId: SessionId("agent-session-1"))
    }

    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse {
        events.append("prompt:\(request.sessionId.value)")
        promptStartedWaiters.forEach { $0.resume() }
        promptStartedWaiters.removeAll()

        if holdNextPrompt {
            holdNextPrompt = false
            return try await withCheckedThrowingContinuation { continuation in
                promptSuspension = continuation
            }
        }
        return SessionPromptResponse(stopReason: .endTurn)
    }

    func handleCancel(_ sessionId: SessionId) async throws {
        events.append("cancel:\(sessionId.value)")
        cancelWaiters.forEach { $0.resume() }
        cancelWaiters.removeAll()
    }

    func handleLoadSession(_ request: LoadSessionRequest) async throws -> LoadSessionResponse {
        events.append("load:\(request.sessionId.value)")
        return LoadSessionResponse()
    }

    func handleResumeSession(_ request: ResumeSessionRequest) async throws -> ResumeSessionResponse {
        let additionalDirectories = request.additionalDirectories?.joined(separator: ",") ?? ""
        events.append("resume:\(request.sessionId.value):\(request.cwd):\(additionalDirectories)")
        return ResumeSessionResponse(
            modes: ModesInfo(
                currentModeId: "chat",
                availableModes: [ModeInfo(id: "chat", name: "Chat")],
            ),
        )
    }

    func handleListSessions(_: ListSessionsRequest) async throws -> ListSessionsResponse {
        events.append("list")
        return ListSessionsResponse(sessions: [])
    }

    func handleDeleteSession(_ request: DeleteSessionRequest) async throws -> DeleteSessionResponse {
        events.append("delete:\(request.sessionId.value)")
        return DeleteSessionResponse()
    }

    func handleCloseSession(_ request: CloseSessionRequest) async throws -> CloseSessionResponse {
        events.append("close:\(request.sessionId.value)")
        return CloseSessionResponse()
    }

    func handleLogout(_: LogoutRequest) async throws -> LogoutResponse {
        events.append("logout")
        return LogoutResponse()
    }

    func handleCancelRequest(_ request: CancelRequestNotification) async throws {
        events.append("cancel-request:\(request.requestId.description)")
        cancelRequestWaiters.forEach { $0.resume() }
        cancelRequestWaiters.removeAll()
    }

    func handleForkSession(_ request: ForkSessionRequest) async throws -> ForkSessionResponse {
        let additionalDirectories = request.additionalDirectories?.joined(separator: ",") ?? ""
        events.append("fork:\(request.sessionId.value):\(request.cwd):\(additionalDirectories)")
        return ForkSessionResponse(sessionId: SessionId("session-forked"))
    }

    func handleListProviders(_: ListProvidersRequest) async throws -> ListProvidersResponse {
        events.append("providers-list")
        return ListProvidersResponse(providers: [
            ProviderInfo(providerId: "anthropic", supported: [.anthropic], required: false),
        ])
    }

    func handleSuggestNes(_ request: SuggestNesRequest) async throws -> SuggestNesResponse {
        events.append("nes-suggest:\(request.sessionId.value):\(request.triggerKind.value)")
        return SuggestNesResponse(suggestions: [
            NesSuggestion(kind: "jump", id: "sug-1", uri: request.uri, position: request.position),
        ])
    }

    func handleRejectNes(_ notification: RejectNesNotification) async throws {
        events
            .append("nes-reject:\(notification.sessionId.value):\(notification.id):\(notification.reason?.value ?? "")")
    }

    func handleDidFocusDocument(_ notification: DidFocusDocumentNotification) async throws {
        events.append("document-focus:\(notification.sessionId.value):\(notification.uri)")
    }

    func handleMcpMessage(_ request: MessageMcpRequest) async throws -> MessageMcpResponse {
        events.append("mcp-message:\(request.connectionId.value):\(request.method)")
        return AnyCodable(["ok": true])
    }

    func handleMcpNotification(_ notification: MessageMcpNotification) async throws {
        events.append("mcp-notification:\(notification.connectionId.value):\(notification.method)")
    }

    func handleSetSessionConfigOption(_ request: SetSessionConfigOptionRequest) async throws
        -> SetSessionConfigOptionResponse
    {
        events.append("config:\(request.configId.value)")
        return SetSessionConfigOptionResponse(configOptions: [])
    }

    // MARK: - Controls

    func recordedEvents() -> [String] {
        events
    }

    /// Makes the next prompt turn suspend inside the delegate until released.
    func suspendNextPromptTurn() {
        holdNextPrompt = true
    }

    func releasePromptTurn(with response: SessionPromptResponse) {
        promptSuspension?.resume(returning: response)
        promptSuspension = nil
    }

    func waitUntilPromptStarted() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            promptStartedWaiters.append(continuation)
        }
    }

    func waitUntilCancelRecorded() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cancelWaiters.append(continuation)
        }
    }

    func waitUntilCancelRequestRecorded() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cancelRequestWaiters.append(continuation)
        }
    }
}

actor RecordingClientDelegate: ClientDelegate {
    private(set) var events: [String] = []

    private var permissionContinuation: CheckedContinuation<RequestPermissionResponse, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var permissionReceived = false

    private func append(_ event: String) {
        events.append(event)
    }

    func handleFileReadRequest(
        _ path: String,
        sessionId _: String,
        line _: Int?,
        limit _: Int?,
    ) async throws -> ReadTextFileResponse {
        append("fs-read:\(path)")
        return ReadTextFileResponse(content: "contents")
    }

    func handleFileWriteRequest(
        _ path: String,
        content _: String,
        sessionId _: String,
    ) async throws -> WriteTextFileResponse {
        append("fs-write:\(path)")
        return WriteTextFileResponse()
    }

    func handleTerminalCreate(
        command _: String,
        sessionId _: String,
        args _: [String]?,
        cwd _: String?,
        env _: [EnvVariable]?,
        outputByteLimit _: Int?,
    ) async throws -> CreateTerminalResponse {
        throw ClientError.unknownMethod("terminal/create")
    }

    func handleTerminalOutput(terminalId _: TerminalId, sessionId _: String) async throws -> TerminalOutputResponse {
        throw ClientError.unknownMethod("terminal/output")
    }

    func handleTerminalWaitForExit(terminalId _: TerminalId, sessionId _: String) async throws -> WaitForExitResponse {
        throw ClientError.unknownMethod("terminal/wait_for_exit")
    }

    func handleTerminalKill(terminalId _: TerminalId, sessionId _: String) async throws -> KillTerminalResponse {
        throw ClientError.unknownMethod("terminal/kill")
    }

    func handleTerminalRelease(terminalId _: TerminalId, sessionId _: String) async throws -> ReleaseTerminalResponse {
        throw ClientError.unknownMethod("terminal/release")
    }

    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse {
        append("permission:\(request.sessionId.value)")
        permissionReceived = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.resume() }

        return await withCheckedContinuation { continuation in
            permissionContinuation = continuation
        }
    }

    func handleMcpConnect(_ request: ConnectMcpRequest) async throws -> ConnectMcpResponse {
        append("mcp-connect:\(request.serverId.value)")
        return ConnectMcpResponse(connectionId: "conn-1")
    }

    func handleMcpNotification(_ notification: MessageMcpNotification) async throws {
        append("mcp-notification:\(notification.connectionId.value):\(notification.method)")
    }

    func handleCreateElicitation(_ request: CreateElicitationRequest) async throws -> CreateElicitationResponse {
        append("elicitation-create:\(request.mode)")
        return CreateElicitationResponse(action: "decline")
    }

    func handleCompleteElicitation(_ notification: CompleteElicitationNotification) async throws {
        append("elicitation-complete:\(notification.elicitationId.value)")
    }

    // MARK: - Controls

    func waitUntilPermissionRequested() async {
        if permissionReceived {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resolvePermission(_ outcome: RequestPermissionResponse) {
        guard let continuation = permissionContinuation else { return }
        permissionContinuation = nil
        continuation.resume(returning: outcome)
    }
}

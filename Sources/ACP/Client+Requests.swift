import ACPModel
import Foundation

public extension Client {
    // MARK: - Other Requests

    func authenticate(
        authMethodId: String,
        credentials: [String: String]? = nil,
    ) async throws -> AuthenticateResponse {
        let request = AuthenticateRequest(
            methodId: authMethodId,
            credentials: credentials,
        )

        let response = try await sendRequest(method: "authenticate", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return AuthenticateResponse(success: true, error: nil)
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return AuthenticateResponse(success: true, error: nil)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        do {
            let data = try encoder.encode(result)
            return try decoder.decode(AuthenticateResponse.self, from: data)
        } catch {
            // Only nil/null/empty results are compatibility successes; a
            // nonempty result that fails to decode is a protocol failure and
            // must never be reported as an authenticated success.
            throw ClientError.invalidResponse
        }
    }

    func setMode(
        sessionId: SessionId,
        modeId: String,
    ) async throws -> SetModeResponse {
        try ensureReadyForSessionOperation()
        let request = SetModeRequest(
            sessionId: sessionId,
            modeId: modeId,
        )

        let response = try await sendRequest(method: "session/set_mode", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return SetModeResponse()
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return SetModeResponse()
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        do {
            let data = try encoder.encode(result)
            return try decoder.decode(SetModeResponse.self, from: data)
        } catch {
            return SetModeResponse()
        }
    }

    func setModel(
        sessionId: SessionId,
        modelId: String,
    ) async throws -> SetModelResponse {
        try ensureReadyForSessionOperation()
        let request = SetModelRequest(
            sessionId: sessionId,
            modelId: modelId,
        )

        let response = try await sendRequest(method: "session/set_model", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        if response.result == nil || (response.result?.value is NSNull) {
            return SetModelResponse()
        }

        if let dict = response.result?.value as? [String: Any], dict.isEmpty {
            return SetModelResponse()
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        do {
            let data = try encoder.encode(result)
            return try decoder.decode(SetModelResponse.self, from: data)
        } catch {
            return SetModelResponse()
        }
    }

    func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigValueId,
    ) async throws -> SetSessionConfigOptionResponse {
        try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .select(value),
        )
    }

    func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: Bool,
    ) async throws -> SetSessionConfigOptionResponse {
        try await setConfigOption(
            sessionId: sessionId,
            configId: configId,
            value: .boolean(value),
        )
    }

    func setConfigOption(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigOptionValue,
    ) async throws -> SetSessionConfigOptionResponse {
        try ensureReadyForSessionOperation()
        let request = SetSessionConfigOptionRequest(
            sessionId: sessionId,
            configId: configId,
            value: value,
        )

        let response = try await sendRequest(method: "session/set_config_option", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SetSessionConfigOptionResponse.self, from: data)
    }

    func listSessions(
        cwd: String? = nil,
        cursor: String? = nil,
        timeout: TimeInterval? = nil,
    ) async throws -> ListSessionsResponse {
        try ensureReadyForSessionOperation()
        let request = ListSessionsRequest(cwd: cwd, cursor: cursor)
        let response = try await sendRequest(method: "session/list", params: request, timeout: timeout)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(ListSessionsResponse.self, from: data)
    }

    func deleteSession(sessionId: SessionId) async throws -> DeleteSessionResponse {
        try ensureReadyForSessionOperation()
        let request = DeleteSessionRequest(sessionId: sessionId)
        let response = try await sendRequest(method: "session/delete", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return try decodeEmptyTolerantResponse(
            DeleteSessionResponse.self,
            from: response,
            emptyValue: DeleteSessionResponse(),
        )
    }

    func logout() async throws -> LogoutResponse {
        let response = try await sendRequest(method: "logout", params: LogoutRequest())

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return try decodeEmptyTolerantResponse(
            LogoutResponse.self,
            from: response,
            emptyValue: LogoutResponse(),
        )
    }

    func listProviders() async throws -> ListProvidersResponse {
        let response = try await sendRequest(method: "providers/list", params: ListProvidersRequest())

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(ListProvidersResponse.self, from: data)
    }

    func setProvider(
        providerId: ProviderId,
        apiType: LlmProtocol,
        baseUrl: String,
        headers: [String: String]? = nil,
    ) async throws -> SetProviderResponse {
        let request = SetProviderRequest(
            providerId: providerId,
            apiType: apiType,
            baseUrl: baseUrl,
            headers: headers,
        )
        let response = try await sendRequest(method: "providers/set", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return try decodeEmptyTolerantResponse(
            SetProviderResponse.self,
            from: response,
            emptyValue: SetProviderResponse(),
        )
    }

    func disableProvider(providerId: ProviderId) async throws -> DisableProviderResponse {
        let request = DisableProviderRequest(providerId: providerId)
        let response = try await sendRequest(method: "providers/disable", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return try decodeEmptyTolerantResponse(
            DisableProviderResponse.self,
            from: response,
            emptyValue: DisableProviderResponse(),
        )
    }

    func startNes(
        workspaceUri: String? = nil,
        workspaceFolders: [WorkspaceFolder]? = nil,
        repository: NesRepository? = nil,
    ) async throws -> StartNesResponse {
        try ensureReadyForSessionOperation()
        let request = StartNesRequest(
            workspaceUri: workspaceUri,
            workspaceFolders: workspaceFolders,
            repository: repository,
        )
        let response = try await sendRequest(method: "nes/start", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(StartNesResponse.self, from: data)
    }

    func suggestNes(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        position: TextPosition,
        selection: ACPModel.TextRange? = nil,
        triggerKind: NesTriggerKind,
        context: NesSuggestContext? = nil,
    ) async throws -> SuggestNesResponse {
        try ensureReadyForSessionOperation()
        let request = SuggestNesRequest(
            sessionId: sessionId,
            uri: uri,
            version: version,
            position: position,
            selection: selection,
            triggerKind: triggerKind,
            context: context,
        )
        let response = try await sendRequest(method: "nes/suggest", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        guard let result = response.result else {
            throw ClientError.invalidResponse
        }

        let data = try encoder.encode(result)
        return try decoder.decode(SuggestNesResponse.self, from: data)
    }

    func acceptNesSuggestion(sessionId: SessionId, id: String) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "nes/accept",
            params: AcceptNesNotification(sessionId: sessionId, id: id),
        )
    }

    func rejectNesSuggestion(sessionId: SessionId, id: String, reason: NesRejectReason? = nil) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "nes/reject",
            params: RejectNesNotification(sessionId: sessionId, id: id, reason: reason),
        )
    }

    func closeNes(sessionId: SessionId) async throws -> CloseNesResponse {
        try ensureReadyForSessionOperation()
        let request = CloseNesRequest(sessionId: sessionId)
        let response = try await sendRequest(method: "nes/close", params: request)

        if let error = response.error {
            throw ClientError.agentError(error)
        }

        return try decodeEmptyTolerantResponse(
            CloseNesResponse.self,
            from: response,
            emptyValue: CloseNesResponse(),
        )
    }

    func sendMcpMessage(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil,
    ) async throws -> MessageMcpResponse {
        try ensureReadyForSessionOperation()
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

    func sendMcpMessageNotification(
        connectionId: McpConnectionId,
        method: String,
        params: AnyCodable? = nil,
    ) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "mcp/message",
            params: MessageMcpNotification(connectionId: connectionId, method: method, params: params),
        )
    }

    func didOpenDocument(
        sessionId: SessionId,
        uri: String,
        languageId: String,
        version: Int64,
        text: String,
    ) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "document/didOpen",
            params: DidOpenDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                languageId: languageId,
                version: version,
                text: text,
            ),
        )
    }

    func didChangeDocument(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        contentChanges: [TextDocumentContentChangeEvent],
    ) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "document/didChange",
            params: DidChangeDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                version: version,
                contentChanges: contentChanges,
            ),
        )
    }

    func didCloseDocument(sessionId: SessionId, uri: String) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "document/didClose",
            params: DidCloseDocumentNotification(sessionId: sessionId, uri: uri),
        )
    }

    func didSaveDocument(sessionId: SessionId, uri: String) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "document/didSave",
            params: DidSaveDocumentNotification(sessionId: sessionId, uri: uri),
        )
    }

    func didFocusDocument(
        sessionId: SessionId,
        uri: String,
        version: Int64,
        position: TextPosition,
        visibleRange: ACPModel.TextRange,
    ) async throws {
        try ensureReadyForSessionOperation()
        try await writeNotification(
            method: "document/didFocus",
            params: DidFocusDocumentNotification(
                sessionId: sessionId,
                uri: uri,
                version: version,
                position: position,
                visibleRange: visibleRange,
            ),
        )
    }

    func sendCancelRequest(requestId: RequestId) async throws {
        try ensureRequestAllowed()
        try await writeNotification(
            method: "$/cancel_request",
            params: CancelRequestNotification(requestId: requestId),
        )
    }
}

// MARK: - Inbound Request Errors

public extension Client {
    struct InboundRouteError: Error {
        let code: Int
        let message: String
        let data: AnyCodable?
    }

    static func inboundRouteError(from error: Error) -> InboundRouteError {
        if let jsonError = error as? JSONRPCError {
            return InboundRouteError(code: jsonError.code, message: jsonError.message, data: jsonError.data)
        }
        if let clientError = error as? ClientError {
            switch clientError {
            case .unknownMethod:
                return InboundRouteError(code: -32601, message: "Method not found", data: nil)
            case .invalidParams:
                return InboundRouteError(code: -32602, message: "Invalid params", data: nil)
            case .invalidResponse:
                return InboundRouteError(code: -32601, message: "Method not found", data: nil)
            case .unsupportedCapability, .delegateNotSet:
                // A privileged request beyond the negotiated capabilities is
                // answered as unsupported, mirroring method-not-supported.
                return InboundRouteError(
                    code: -32601,
                    message: "Method not supported by negotiated capabilities",
                    data: nil,
                )
            default:
                break
            }
        }
        if error is DecodingError {
            return InboundRouteError(code: -32602, message: "Invalid params", data: nil)
        }
        // Fixed, payload-free internal error message.
        return InboundRouteError(code: -32603, message: "Internal error", data: nil)
    }
}

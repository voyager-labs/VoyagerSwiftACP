import ACPModel

/// Protocol for handling agent operations
public protocol AgentDelegate: AnyObject, Sendable {
    /// Handle initialization request from client
    func handleInitialize(_ request: InitializeRequest) async throws -> InitializeResponse

    /// Handle new session request
    func handleNewSession(_ request: NewSessionRequest) async throws -> NewSessionResponse

    /// Handle prompt request - the main interaction point
    func handlePrompt(_ request: SessionPromptRequest) async throws -> SessionPromptResponse

    /// Handle session cancellation
    func handleCancel(_ sessionId: SessionId) async throws

    /// Handle session load request
    func handleLoadSession(_ request: LoadSessionRequest) async throws -> LoadSessionResponse

    /// Handle session resume request
    func handleResumeSession(_ request: ResumeSessionRequest) async throws -> ResumeSessionResponse

    /// Handle session listing request
    func handleListSessions(_ request: ListSessionsRequest) async throws -> ListSessionsResponse

    /// Handle session delete request
    func handleDeleteSession(_ request: DeleteSessionRequest) async throws -> DeleteSessionResponse

    /// Handle session close request
    func handleCloseSession(_ request: CloseSessionRequest) async throws -> CloseSessionResponse

    /// Handle logout request
    func handleLogout(_ request: LogoutRequest) async throws -> LogoutResponse

    /// Handle protocol-level request cancellation notification
    func handleCancelRequest(_ request: CancelRequestNotification) async throws

    /// Handle fork session request
    func handleForkSession(_ request: ForkSessionRequest) async throws -> ForkSessionResponse

    /// Handle provider listing request
    func handleListProviders(_ request: ListProvidersRequest) async throws -> ListProvidersResponse

    /// Handle provider configuration request
    func handleSetProvider(_ request: SetProviderRequest) async throws -> SetProviderResponse

    /// Handle provider disable request
    func handleDisableProvider(_ request: DisableProviderRequest) async throws -> DisableProviderResponse

    /// Handle NES session start request
    func handleStartNes(_ request: StartNesRequest) async throws -> StartNesResponse

    /// Handle NES suggestion request
    func handleSuggestNes(_ request: SuggestNesRequest) async throws -> SuggestNesResponse

    /// Handle NES close request
    func handleCloseNes(_ request: CloseNesRequest) async throws -> CloseNesResponse

    /// Handle NES accepted suggestion notification
    func handleAcceptNes(_ notification: AcceptNesNotification) async throws

    /// Handle NES rejected suggestion notification
    func handleRejectNes(_ notification: RejectNesNotification) async throws

    /// Handle document open notification
    func handleDidOpenDocument(_ notification: DidOpenDocumentNotification) async throws

    /// Handle document change notification
    func handleDidChangeDocument(_ notification: DidChangeDocumentNotification) async throws

    /// Handle document close notification
    func handleDidCloseDocument(_ notification: DidCloseDocumentNotification) async throws

    /// Handle document save notification
    func handleDidSaveDocument(_ notification: DidSaveDocumentNotification) async throws

    /// Handle document focus notification
    func handleDidFocusDocument(_ notification: DidFocusDocumentNotification) async throws

    /// Handle MCP-over-ACP request message
    func handleMcpMessage(_ request: MessageMcpRequest) async throws -> MessageMcpResponse

    /// Handle MCP-over-ACP notification message
    func handleMcpNotification(_ notification: MessageMcpNotification) async throws

    /// Handle session config option changes from the client (VOY-700 generic
    /// gap: the wire method previously fell through to the custom stream).
    func handleSetSessionConfigOption(_ request: SetSessionConfigOptionRequest) async throws
        -> SetSessionConfigOptionResponse
}

/// Default implementations for optional delegate methods
public extension AgentDelegate {
    func handleCancel(_: SessionId) async throws {
        // Default: no-op
    }

    func handleLoadSession(_: LoadSessionRequest) async throws -> LoadSessionResponse {
        throw ClientError.unknownMethod("session/load")
    }

    func handleResumeSession(_: ResumeSessionRequest) async throws -> ResumeSessionResponse {
        throw ClientError.unknownMethod("session/resume")
    }

    func handleListSessions(_: ListSessionsRequest) async throws -> ListSessionsResponse {
        throw ClientError.unknownMethod("session/list")
    }

    func handleDeleteSession(_: DeleteSessionRequest) async throws -> DeleteSessionResponse {
        throw ClientError.unknownMethod("session/delete")
    }

    func handleCloseSession(_: CloseSessionRequest) async throws -> CloseSessionResponse {
        throw ClientError.unknownMethod("session/close")
    }

    func handleLogout(_: LogoutRequest) async throws -> LogoutResponse {
        throw ClientError.unknownMethod("logout")
    }

    func handleCancelRequest(_: CancelRequestNotification) async throws {
        // Default: no-op
    }

    func handleForkSession(_: ForkSessionRequest) async throws -> ForkSessionResponse {
        throw ClientError.unknownMethod("session/fork")
    }

    func handleListProviders(_: ListProvidersRequest) async throws -> ListProvidersResponse {
        throw ClientError.unknownMethod("providers/list")
    }

    func handleSetProvider(_: SetProviderRequest) async throws -> SetProviderResponse {
        throw ClientError.unknownMethod("providers/set")
    }

    func handleDisableProvider(_: DisableProviderRequest) async throws -> DisableProviderResponse {
        throw ClientError.unknownMethod("providers/disable")
    }

    func handleStartNes(_: StartNesRequest) async throws -> StartNesResponse {
        throw ClientError.unknownMethod("nes/start")
    }

    func handleSuggestNes(_: SuggestNesRequest) async throws -> SuggestNesResponse {
        throw ClientError.unknownMethod("nes/suggest")
    }

    func handleCloseNes(_: CloseNesRequest) async throws -> CloseNesResponse {
        throw ClientError.unknownMethod("nes/close")
    }

    func handleAcceptNes(_: AcceptNesNotification) async throws {
        // Default: no-op
    }

    func handleRejectNes(_: RejectNesNotification) async throws {
        // Default: no-op
    }

    func handleDidOpenDocument(_: DidOpenDocumentNotification) async throws {
        // Default: no-op
    }

    func handleDidChangeDocument(_: DidChangeDocumentNotification) async throws {
        // Default: no-op
    }

    func handleDidCloseDocument(_: DidCloseDocumentNotification) async throws {
        // Default: no-op
    }

    func handleDidSaveDocument(_: DidSaveDocumentNotification) async throws {
        // Default: no-op
    }

    func handleDidFocusDocument(_: DidFocusDocumentNotification) async throws {
        // Default: no-op
    }

    func handleMcpMessage(_: MessageMcpRequest) async throws -> MessageMcpResponse {
        throw ClientError.unknownMethod("mcp/message")
    }

    func handleMcpNotification(_: MessageMcpNotification) async throws {
        // Default: no-op
    }

    /// Handle session config option changes from the client. The default keeps
    /// the method explicitly unsupported on the wire.
    func handleSetSessionConfigOption(_: SetSessionConfigOptionRequest) async throws -> SetSessionConfigOptionResponse {
        throw ClientError.unknownMethod("session/set_config_option")
    }
}

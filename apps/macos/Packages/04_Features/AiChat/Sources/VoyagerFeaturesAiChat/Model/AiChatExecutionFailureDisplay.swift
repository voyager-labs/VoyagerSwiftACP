import VoyagerEntitiesAi

extension AiChatExecutionFailure {
    var displayMessage: String {
        switch self {
        case .cancelled:
            "The request was cancelled."
        case .authentication:
            "Authentication with the chat provider failed."
        case .modelUnavailable:
            "The selected model is unavailable."
        case .network:
            "The network connection to the chat provider failed."
        case .rateLimited:
            "The chat provider rate limit was reached. Please wait and try again."
        case .quotaExceeded:
            "The chat provider rejected the request because the account quota, credits, or billing limit was exceeded."
        case .invalidRequest:
            "The chat request could not be sent."
        case .transportError:
            "The chat service response could not be read."
        case .cliUnavailable:
            "The Codex CLI could not be launched. Make sure the codex command is installed and available to Voyager."
        case .unsupportedProvider:
            "This provider is not supported for chat."
        case .sessionMismatch:
            "The current session no longer matches the active request."
        case .unknown:
            "An unknown chat error occurred."
        }
    }
}

extension AiProvider {
    var supportsAiChatExecution: Bool {
        true
    }
}

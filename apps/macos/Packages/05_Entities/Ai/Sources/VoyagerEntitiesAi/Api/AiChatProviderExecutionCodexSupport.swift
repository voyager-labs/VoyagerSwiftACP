import Foundation

struct SSEPayloadAccumulator {
    private var dataLines: [String] = []

    mutating func consume(_ line: String) -> [String] {
        let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        guard !normalized.isEmpty else {
            guard let payload = finish() else { return [] }
            return [payload]
        }
        guard normalized.hasPrefix("data:") else { return [] }
        dataLines.append(String(normalized.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        return []
    }

    mutating func finish() -> String? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines = [] }
        return dataLines.joined(separator: "\n")
    }
}

extension AiChatProviderExecutionClient {
    nonisolated static func codexFailureReason(forCLIErrorOutput message: String) -> AiChatExecutionFailure {
        let lowered = message.lowercased()
        if lowered.containsCodexTransportFailure || lowered.containsAny(codexNetworkFailureMarkers) { return .network }
        if lowered.containsAny(codexAuthenticationFailureMarkers) { return .authentication }
        if lowered.containsAny(codexRateLimitFailureMarkers) { return .rateLimited }
        if lowered.containsAny(codexQuotaFailureMarkers) { return .quotaExceeded }
        if lowered.contains("model"),
           lowered.containsAny(codexModelUnavailableFailureMarkers) { return .modelUnavailable }
        return .invalidRequest
    }

    nonisolated private static let codexNetworkFailureMarkers = [
        "auth check failed", "network", "offline", "not connected", "internet connection", "timed out",
        "timeout", "connection refused", "connection reset", "host unreachable", "enotfound", "econnreset",
        "econnrefused", "eai_again",
    ]
    nonisolated private static let codexAuthenticationFailureMarkers = [
        "unauthorized", "login required", "not logged in", "sign in required", "invalid token", "expired token",
        "invalid credential", "missing credential",
    ]
    nonisolated private static let codexRateLimitFailureMarkers = ["rate limit", "too many requests"]
    nonisolated private static let codexQuotaFailureMarkers = [
        "credit", "quota", "billing", "balance", "payment", "usage limit", "limit reached", "monthly limit",
        "daily limit", "spending limit", "plan limit", "current quota", "billing details", "maximum monthly spend",
        "monthly budget", "hard limit", "soft limit", "usage cap", "insufficient funds", "upgrade", "subscription",
    ]
    nonisolated private static let codexModelUnavailableFailureMarkers = ["not found", "unknown"]
}

private extension String {
    var containsCodexTransportFailure: Bool {
        (contains("request") && contains("url") && (contains("failed") || contains("error sending")))
            || contains("http/request failed")
            || (contains("websocket") && contains("failed to connect"))
            || contains("failed to lookup address information")
            || contains("failed to resolve")
            || contains("could not resolve")
            || contains("stream disconnected")
            || (contains("transport") && contains("closed"))
    }

    func containsAny(_ markers: [String]) -> Bool {
        markers.contains { contains($0) }
    }
}

enum CodexCLIExecutionError: Error, Equatable {
    case launchFailed
    case readinessFailed(CodexExecReadinessError)
    case outputMissing(String)
    case nonZeroExit(String)
    case protocolFailure(AiChatExecutionFailure)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .launchFailed: .cliUnavailable
        case let .readinessFailed(error):
            switch error {
            case .executableMissing, .versionUnreadable, .unsupportedVersion: .cliUnavailable
            case .loginRequired, .loginProbeFailed: .authentication
            case .probeTimeout: .network
            }
        case let .outputMissing(message), let .nonZeroExit(message):
            AiChatProviderExecutionClient.codexFailureReason(forCLIErrorOutput: message)
        case let .protocolFailure(reason): reason
        }
    }
}

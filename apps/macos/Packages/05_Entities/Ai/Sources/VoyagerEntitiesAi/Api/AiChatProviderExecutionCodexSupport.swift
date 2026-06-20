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
        let payloadLine = String(normalized.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        dataLines.append(payloadLine)
        return []
    }

    mutating func finish() -> String? {
        guard !dataLines.isEmpty else { return nil }
        defer { dataLines = [] }
        return dataLines.joined(separator: "\n")
    }
}

final class CodexProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var completed = false
    private var cancelled = false
    private let cleanupURLs: [URL]

    init(cleanupURLs: [URL]) {
        self.cleanupURLs = cleanupURLs
    }

    func set(process: Process) {
        lock.lock()
        if completed || cancelled {
            lock.unlock()
            if process.isRunning { process.terminate() }
            return
        }
        self.process = process
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = process
        lock.unlock()

        if let process, process.isRunning {
            process.terminate()
        }
    }

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    func cleanup() {
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

final class CodexPipeDataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func stringValue() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

final class CodexJSONLineParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let onDelta: @Sendable (String) -> Void

    init(onDelta: @escaping @Sendable (String) -> Void) {
        self.onDelta = onDelta
    }

    func append(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
        lock.lock()
        buffer.append(chunk)
        let lines = buffer.components(separatedBy: .newlines)
        buffer = lines.last ?? ""
        lock.unlock()
        for line in lines.dropLast() {
            process(line)
        }
    }

    func finish() {
        lock.lock()
        let line = buffer
        buffer = ""
        lock.unlock()
        process(line)
    }

    private func process(_ line: String) {
        guard
            let delta = AiChatProviderExecutionClient.codexAgentMessageDelta(fromJSONLine: line),
            !delta.isEmpty
        else {
            return
        }
        onDelta(delta)
    }
}

extension AiChatProviderExecutionClient {
    nonisolated static func codexAgentMessageDelta(fromJSONLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CodexJSONEvent.self, from: data).agentMessageDelta
    }

    nonisolated static func codexFailureReason(forCLIErrorOutput message: String) -> AiChatExecutionFailure {
        let lowered = message.lowercased()
        if lowered.containsCodexTransportFailure || lowered.containsAny(codexNetworkFailureMarkers) {
            return .network
        }
        if lowered.containsAny(codexAuthenticationFailureMarkers) {
            return .authentication
        }
        if lowered.containsAny(codexRateLimitFailureMarkers) {
            return .rateLimited
        }
        if lowered.containsAny(codexQuotaFailureMarkers) {
            return .quotaExceeded
        }
        if lowered.contains("model"), lowered.containsAny(codexModelUnavailableFailureMarkers) {
            return .modelUnavailable
        }
        return .invalidRequest
    }

    nonisolated private static let codexNetworkFailureMarkers = [
        "auth check failed",
        "network",
        "offline",
        "not connected",
        "internet connection",
        "timed out",
        "timeout",
        "connection refused",
        "connection reset",
        "host unreachable",
        "enotfound",
        "econnreset",
        "econnrefused",
        "eai_again",
    ]

    nonisolated private static let codexAuthenticationFailureMarkers = [
        "unauthorized",
        "login required",
        "not logged in",
        "sign in required",
        "invalid token",
        "expired token",
        "invalid credential",
        "missing credential",
    ]

    nonisolated private static let codexRateLimitFailureMarkers = [
        "rate limit",
        "too many requests",
    ]

    nonisolated private static let codexQuotaFailureMarkers = [
        "credit",
        "quota",
        "billing",
        "balance",
        "payment",
        "usage limit",
        "limit reached",
        "monthly limit",
        "daily limit",
        "spending limit",
        "plan limit",
        "current quota",
        "billing details",
        "maximum monthly spend",
        "monthly budget",
        "hard limit",
        "soft limit",
        "usage cap",
        "insufficient funds",
        "upgrade",
        "subscription",
    ]

    nonisolated private static let codexModelUnavailableFailureMarkers = [
        "not found",
        "unknown",
    ]
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

struct CodexJSONEvent: Decodable {
    let type: String?
    let method: String?
    let item: CodexJSONItem?
    let params: CodexJSONParams?
    let delta: String?

    var agentMessageDelta: String? {
        let normalizedMethod = method?.lowercased() ?? ""
        if normalizedMethod.contains("agentmessage/delta")
            || normalizedMethod.contains("agent_message/delta")
            || normalizedMethod.contains("agent-message/delta")
        {
            return params?.delta ?? params?.text ?? delta
        }
        if normalizedMethod == "item/completed" || normalizedMethod == "item.completed" {
            return params?.item?.agentMessageText ?? params?.text ?? delta
        }

        let normalizedType = type?.lowercased() ?? ""
        guard ["item.delta", "item.updated", "item.completed"].contains(normalizedType) else {
            return nil
        }
        guard item?.isAssistantMessage == true else {
            return nil
        }
        return item?.text ?? item?.contentText ?? params?.delta ?? params?.text ?? delta
    }
}

struct CodexJSONParams: Decodable {
    let delta: String?
    let text: String?
    let item: CodexJSONItem?
}

struct CodexJSONItem: Decodable {
    let type: String?
    let role: String?
    let text: String?
    let content: [CodexJSONContent]?

    var isAssistantMessage: Bool {
        let normalizedType = type?.lowercased() ?? ""
        let normalizedRole = role?.lowercased() ?? ""
        return normalizedType == "agent_message"
            || normalizedType == "message" && normalizedRole == "assistant"
            || normalizedType == "assistant_message"
    }

    var agentMessageText: String? {
        guard isAssistantMessage else { return nil }
        return text ?? contentText
    }

    var contentText: String? {
        let text = content?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

struct CodexJSONContent: Decodable {
    let type: String?
    let text: String?
}

struct CodexCLIAuthFile: Encodable {
    let tokens: CodexCLIAuthTokens
    let lastRefresh: String

    init(credential: OAuthCredentialFile) {
        tokens = CodexCLIAuthTokens(credential: credential)
        lastRefresh = ISO8601DateFormatter().string(from: Date())
    }

    enum CodingKeys: String, CodingKey {
        case tokens
        case lastRefresh = "last_refresh"
    }
}

struct CodexCLIAuthTokens: Encodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let accountID: String?

    init(credential: OAuthCredentialFile) {
        accessToken = credential.accessToken
        refreshToken = credential.refreshToken
        idToken = credential.idToken
        accountID = credential.chatGPTAccountId
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

enum CodexCLIExecutionError: Error, Equatable {
    case launchFailed
    case outputMissing(String)
    case nonZeroExit(String)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .launchFailed:
            .cliUnavailable
        case let .outputMissing(message), let .nonZeroExit(message):
            AiChatProviderExecutionClient.codexFailureReason(forCLIErrorOutput: message)
        }
    }
}

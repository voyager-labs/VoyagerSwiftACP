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
        if let process, process.isRunning { process.terminate() }
    }

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
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

final class CodexJSONLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[..<newlineIndex]))
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    func finish() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll(keepingCapacity: false) }
        return buffer
    }
}

final class CodexAppServerProtocolDriver: @unchecked Sendable {
    private let lock = NSLock()
    private let lineBuffer = CodexJSONLineBuffer()
    private var finalText = ""
    private let input: FileHandle
    private let model: String
    private let prompt: String
    private let thinking: AiChatProviderThinkingPayload?
    private let workingDirectory: URL?
    private let onEvent: @Sendable (CodexAppServerEvent) -> Void
    private let onComplete: @Sendable (Result<String, Error>) -> Void

    init(
        input: FileHandle,
        model: String,
        prompt: String,
        thinking: AiChatProviderThinkingPayload?,
        workingDirectory: URL?,
        onEvent: @escaping @Sendable (CodexAppServerEvent) -> Void,
        onComplete: @escaping @Sendable (Result<String, Error>) -> Void,
    ) {
        self.input = input
        self.model = model
        self.prompt = prompt
        self.thinking = thinking
        self.workingDirectory = workingDirectory
        self.onEvent = onEvent
        self.onComplete = onComplete
    }

    func start() throws {
        try send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "Voyager", "version": "1"],
                "capabilities": ["experimentalApi": false],
            ],
        ])
    }

    func append(_ data: Data) {
        for line in lineBuffer.append(data) {
            process(line)
        }
    }

    func finish() {
        if let line = lineBuffer.finish() { process(line) }
    }

    private func process(_ data: Data) {
        guard !data.isEmpty else { return }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexAppServerParsingError.malformedKnownEvent("json-rpc")
            }
            if let id = object["id"] as? Int {
                try processResponse(id: id, object: object)
                return
            }
            if let event = try AiChatProviderExecutionClient.codexAppServerEvent(fromJSONObject: object) {
                handle(event)
            }
        } catch {
            onComplete(.failure(error))
        }
    }

    private func handle(_ event: CodexAppServerEvent) {
        if case let .agentMessageDelta(_, delta) = event { appendFinalText(delta) }
        onEvent(event)
        guard case let .turnCompleted(_, status, failure, _) = event else { return }
        completeTurn(status: status, failure: failure)
    }

    private func completeTurn(
        status: CodexAppServerTurnStatus,
        failure: AiChatExecutionFailure?,
    ) {
        switch status {
        case .completed:
            onComplete(.success(finalTextSnapshot()))
        case .failed:
            onComplete(.failure(CodexCLIExecutionError.protocolFailure(failure ?? .invalidRequest)))
        case .interrupted:
            onComplete(.failure(CancellationError()))
        case .inProgress:
            onComplete(.failure(CodexAppServerParsingError.malformedKnownEvent("turn/completed")))
        }
    }

    private func processResponse(id: Int, object: [String: Any]) throws {
        if object["error"] != nil {
            throw CodexCLIExecutionError.protocolFailure(.transportError)
        }
        guard let result = object["result"] as? [String: Any] else {
            throw CodexAppServerParsingError.malformedKnownEvent("response")
        }
        switch id {
        case 1:
            try send(["method": "initialized"])
            var params: [String: Any] = [
                "model": model,
                "ephemeral": true,
                "approvalPolicy": "never",
                "sandbox": "workspace-write",
            ]
            if let path = workingDirectory?.path { params["cwd"] = path }
            try send(["id": 2, "method": "thread/start", "params": params])
        case 2:
            guard let thread = result["thread"] as? [String: Any], let threadID = thread["id"] as? String else {
                throw CodexAppServerParsingError.malformedKnownEvent("thread/start")
            }
            var params: [String: Any] = [
                "threadId": threadID,
                "input": [["type": "text", "text": prompt]],
                "model": model,
            ]
            if let effort = AiChatProviderExecutionClient.codexReasoningEffort(from: thinking) {
                params["effort"] = effort
            }
            try send(["id": 3, "method": "turn/start", "params": params])
        case 3:
            guard result["turn"] is [String: Any] else {
                throw CodexAppServerParsingError.malformedKnownEvent("turn/start")
            }
        default:
            break
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func appendFinalText(_ delta: String) {
        lock.lock()
        finalText.append(delta)
        lock.unlock()
    }

    private func finalTextSnapshot() -> String {
        lock.lock()
        let snapshot = finalText
        lock.unlock()
        return snapshot
    }
}

extension AiChatProviderExecutionClient {
    nonisolated static func codexAppServerEvent(fromJSONLine line: String) throws -> CodexAppServerEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAppServerParsingError.malformedKnownEvent("json-rpc")
        }
        return try codexAppServerEvent(fromJSONObject: object)
    }

    nonisolated static func codexAppServerEvent(
        fromJSONObject object: [String: Any],
    ) throws -> CodexAppServerEvent? {
        guard let method = object["method"] as? String else { return nil }
        guard let params = object["params"] as? [String: Any] else {
            if isKnownCodexMethod(method) { throw CodexAppServerParsingError.malformedKnownEvent(method) }
            return nil
        }
        return try codexAppServerEvent(method: method, params: params)
    }

    private static func codexAppServerEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent? {
        switch method {
        case "turn/started":
            try codexTurnStartedEvent(method: method, params: params)
        case "turn/completed":
            try codexTurnCompletedEvent(method: method, params: params)
        case "item/started", "item/completed":
            try codexItemEvent(method: method, params: params)
        case "item/agentMessage/delta":
            try codexAgentMessageDeltaEvent(method: method, params: params)
        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            try codexReasoningDeltaEvent(method: method, params: params)
        case "error":
            try codexErrorEvent(method: method, params: params)
        default:
            nil
        }
    }

    private static func codexTurnStartedEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent {
        guard let turn = params["turn"] as? [String: Any], let id = turn["id"] as? String else {
            throw CodexAppServerParsingError.malformedKnownEvent(method)
        }
        return .turnStarted(turnID: id, providerEventType: method)
    }

    private static func codexTurnCompletedEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent {
        guard let turn = params["turn"] as? [String: Any],
              let id = turn["id"] as? String,
              let rawStatus = turn["status"] as? String,
              let status = CodexAppServerTurnStatus(rawValue: rawStatus),
              status != .inProgress
        else { throw CodexAppServerParsingError.malformedKnownEvent(method) }
        let failure = (turn["error"] as? [String: Any])?["message"] as? String
        return .turnCompleted(
            turnID: id,
            status: status,
            failure: failure.map(codexFailureReason(forCLIErrorOutput:)),
            providerEventType: method,
        )
    }

    private static func codexItemEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent? {
        guard let item = params["item"] as? [String: Any],
              let id = item["id"] as? String,
              let type = item["type"] as? String
        else { throw CodexAppServerParsingError.malformedKnownEvent(method) }
        guard let kind = codexItemKind(type: type, phase: item["phase"] as? String) else { return nil }
        if method == "item/started" {
            return .itemStarted(id: id, kind: kind, providerEventType: method)
        }
        return .itemCompleted(id: id, kind: kind, providerEventType: method)
    }

    private static func codexAgentMessageDeltaEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent {
        guard let itemID = params["itemId"] as? String, let delta = params["delta"] as? String else {
            throw CodexAppServerParsingError.malformedKnownEvent(method)
        }
        return .agentMessageDelta(itemID: itemID, delta: delta)
    }

    private static func codexReasoningDeltaEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent {
        guard let itemID = params["itemId"] as? String, params["delta"] is String else {
            throw CodexAppServerParsingError.malformedKnownEvent(method)
        }
        return .reasoningDelta(itemID: itemID)
    }

    private static func codexErrorEvent(
        method: String,
        params: [String: Any],
    ) throws -> CodexAppServerEvent {
        guard let turnID = params["turnId"] as? String,
              let willRetry = params["willRetry"] as? Bool,
              params["error"] is [String: Any]
        else { throw CodexAppServerParsingError.malformedKnownEvent(method) }
        return .error(turnID: turnID, willRetry: willRetry, providerEventType: method)
    }

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

    private static func isKnownCodexMethod(_ method: String) -> Bool {
        [
            "turn/started",
            "turn/completed",
            "item/started",
            "item/completed",
            "item/agentMessage/delta",
            "item/reasoning/summaryTextDelta",
            "item/reasoning/textDelta",
            "error",
        ].contains(method)
    }

    private static func codexItemKind(type: String, phase: String?) -> CodexAppServerItemKind? {
        switch type {
        case "reasoning": .reasoning
        case "webSearch": .webSearch
        case "commandExecution": .commandExecution
        case "mcpToolCall": .mcpToolCall
        case "agentMessage": .agentMessage(phase: phase)
        default: nil
        }
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
    case protocolFailure(AiChatExecutionFailure)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .launchFailed: .cliUnavailable
        case let .outputMissing(message), let .nonZeroExit(message):
            AiChatProviderExecutionClient.codexFailureReason(forCLIErrorOutput: message)
        case let .protocolFailure(reason): reason
        }
    }
}

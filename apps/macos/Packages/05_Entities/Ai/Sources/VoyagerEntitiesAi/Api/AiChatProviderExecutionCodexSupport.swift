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
    private let maximumBytes: Int
    private let onLimitExceeded: @Sendable () -> Void
    private var data = Data()

    init(maximumBytes: Int, onLimitExceeded: @escaping @Sendable () -> Void) {
        self.maximumBytes = maximumBytes
        self.onLimitExceeded = onLimitExceeded
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        let canAppend = chunk.count <= maximumBytes - data.count
        if canAppend { data.append(chunk) }
        lock.unlock()
        if !canAppend { onLimitExceeded() }
    }

    func stringValue() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

final class CodexJSONLineBuffer {
    private var buffer = Data()

    func append(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            guard newlineIndex <= CodexAppServerProtocolLimits.maximumRawJSONLineBytes else {
                buffer.removeAll(keepingCapacity: false)
                throw CodexAppServerParsingError.resourceLimitExceeded(.rawJSONLineBytes)
            }
            lines.append(Data(buffer[..<newlineIndex]))
            buffer.removeSubrange(...newlineIndex)
        }
        guard buffer.count <= CodexAppServerProtocolLimits.maximumRawJSONLineBytes else {
            buffer.removeAll(keepingCapacity: false)
            throw CodexAppServerParsingError.resourceLimitExceeded(.rawJSONLineBytes)
        }
        return lines
    }

    func finish() -> Data? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll(keepingCapacity: false) }
        return buffer
    }
}

final class CodexAppServerProtocolDriver: @unchecked Sendable {
    private struct AgentMessageText {
        var accumulatedDelta = ""
        var completedText: String?

        var resolved: String {
            completedText ?? accumulatedDelta
        }
    }

    private enum Operation {
        case append(Data)
        case fail(CodexAppServerParsingError)
        case finish
    }

    private let executor = DispatchQueue(label: "com.voyager.codex-app-server-protocol")
    private let executorKey = DispatchSpecificKey<UInt8>()
    private let lineBuffer = CodexJSONLineBuffer()
    private var pendingOperations: [Operation] = []
    private var pendingOperationIndex = 0
    private var isDrainingOperations = false
    private var isTerminated = false
    private var isInputFinished = false
    private var agentMessageItemIDs: [String] = []
    private var agentMessageTextsByItemID: [String: AgentMessageText] = [:]
    private var storedTextUTF8Bytes = 0
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
        self.workingDirectory = workingDirectory.map(CodexPathCanonicalizer.url)
        self.onEvent = onEvent
        self.onComplete = onComplete
        executor.setSpecific(key: executorKey, value: 1)
    }

    func start() throws {
        try executor.sync {
            try send([
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "Voyager", "version": "1"],
                    "capabilities": ["experimentalApi": true],
                ],
            ])
        }
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        submit(.append(data))
    }

    func fail(_ error: CodexAppServerParsingError) {
        submit(.fail(error))
    }

    func finish() {
        submit(.finish)
    }

    private func submit(_ operation: Operation) {
        if DispatchQueue.getSpecific(key: executorKey) != nil {
            pendingOperations.append(operation)
            return
        }
        executor.sync {
            pendingOperations.append(operation)
            drainOperations()
        }
    }

    private func drainOperations() {
        guard !isDrainingOperations else { return }
        isDrainingOperations = true
        defer {
            pendingOperations.removeAll(keepingCapacity: true)
            pendingOperationIndex = 0
            isDrainingOperations = false
        }
        while pendingOperationIndex < pendingOperations.count {
            let operation = pendingOperations[pendingOperationIndex]
            pendingOperationIndex += 1
            execute(operation)
        }
    }

    private func execute(_ operation: Operation) {
        guard !isTerminated else { return }
        switch operation {
        case let .append(data):
            guard !isInputFinished else { return }
            do {
                for line in try lineBuffer.append(data) {
                    guard !isTerminated else { break }
                    process(line)
                }
            } catch let error as CodexAppServerParsingError {
                terminate(with: .failure(error))
            } catch {
                terminate(with: .failure(error))
            }
        case let .fail(error):
            terminate(with: .failure(error))
        case .finish:
            guard !isInputFinished else { return }
            isInputFinished = true
            if let line = lineBuffer.finish() { process(line) }
        }
    }

    private func process(_ data: Data) {
        guard !data.isEmpty, !isTerminated else { return }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexAppServerParsingError.malformedKnownEvent("json-rpc")
            }
            if let id = object["id"] as? Int {
                try processResponse(id: id, object: object)
                return
            }
            if let event = try AiChatProviderExecutionClient.codexAppServerEvent(fromJSONObject: object) {
                try handle(event)
            }
        } catch {
            terminate(with: .failure(error))
        }
    }

    private func handle(_ event: CodexAppServerEvent) throws {
        switch event {
        case let .itemStarted(id, .agentMessage, _):
            try registerAgentMessageItem(id)
        case let .agentMessageDelta(itemID, delta):
            try appendAgentMessageDelta(delta, itemID: itemID)
        case let .itemCompleted(id, .agentMessage, completedText, _):
            try completeAgentMessageItem(id, text: completedText)
        case let .turnCompleted(_, status, failure, _):
            let result = turnResult(status: status, failure: failure)
            isTerminated = true
            onEvent(event)
            onComplete(result)
            return
        default:
            break
        }
        onEvent(event)
    }

    private func turnResult(
        status: CodexAppServerTurnStatus,
        failure: AiChatExecutionFailure?,
    ) -> Result<String, Error> {
        switch status {
        case .completed:
            .success(finalTextSnapshot())
        case .failed:
            .failure(CodexCLIExecutionError.protocolFailure(failure ?? .invalidRequest))
        case .interrupted:
            .failure(CancellationError())
        case .inProgress:
            .failure(CodexAppServerParsingError.malformedKnownEvent("turn/completed"))
        }
    }

    private func terminate(with result: Result<String, Error>) {
        guard !isTerminated else { return }
        isTerminated = true
        onComplete(result)
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
            try sendThreadStartRequest()
        case 2:
            try sendTurnStartRequest(result: result)
        case 3:
            try validateTurnStartResponse(result)
        default:
            break
        }
    }

    private func sendThreadStartRequest() throws {
        try send(["method": "initialized"])
        var params: [String: Any] = [
            "model": model,
            "ephemeral": true,
            "approvalPolicy": "never",
            "permissions": CodexReferencePermissionProfile.identifier,
        ]
        if let path = workingDirectory?.path { params["cwd"] = path }
        try send(["id": 2, "method": "thread/start", "params": params])
    }

    private func sendTurnStartRequest(result: [String: Any]) throws {
        guard let thread = result["thread"] as? [String: Any], let threadID = thread["id"] as? String,
              validatesReferencePermissionProfile(result)
        else {
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
    }

    private func validateTurnStartResponse(_ result: [String: Any]) throws {
        guard result["turn"] is [String: Any] else {
            throw CodexAppServerParsingError.malformedKnownEvent("turn/start")
        }
    }

    private func validatesReferencePermissionProfile(_ result: [String: Any]) -> Bool {
        guard let expectedPath = workingDirectory?.standardizedFileURL.path,
              let profile = result["activePermissionProfile"] as? [String: Any],
              profile["id"] as? String == CodexReferencePermissionProfile.identifier,
              let sandbox = result["sandbox"] as? [String: Any],
              sandbox["type"] as? String == "readOnly",
              sandbox["networkAccess"] as? Bool == false,
              result["approvalPolicy"] as? String == "never",
              result["cwd"] as? String == expectedPath,
              result["runtimeWorkspaceRoots"] as? [String] == [expectedPath]
        else {
            return false
        }
        return true
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func registerAgentMessageItem(_ itemID: String) throws {
        guard itemID.utf8.count <= CodexAppServerProtocolLimits.maximumItemIDUTF8Bytes else {
            throw CodexAppServerParsingError.resourceLimitExceeded(.itemIDUTF8Bytes)
        }
        guard agentMessageTextsByItemID[itemID] == nil else { return }
        guard agentMessageItemIDs.count < CodexAppServerProtocolLimits.maximumAgentMessageItemCount else {
            throw CodexAppServerParsingError.resourceLimitExceeded(.agentMessageItemCount)
        }
        agentMessageItemIDs.append(itemID)
        agentMessageTextsByItemID[itemID] = AgentMessageText()
    }

    private func appendAgentMessageDelta(_ delta: String, itemID: String) throws {
        try registerAgentMessageItem(itemID)
        guard var item = agentMessageTextsByItemID[itemID], item.completedText == nil else { return }
        let deltaUTF8Bytes = delta.utf8.count
        try validateStoredTextUTF8Bytes(storedTextUTF8Bytes + deltaUTF8Bytes)
        item.accumulatedDelta.append(delta)
        storedTextUTF8Bytes += deltaUTF8Bytes
        agentMessageTextsByItemID[itemID] = item
    }

    private func completeAgentMessageItem(_ itemID: String, text: String?) throws {
        try registerAgentMessageItem(itemID)
        guard let text, var item = agentMessageTextsByItemID[itemID] else { return }
        guard item.completedText != text else { return }
        let replacedUTF8Bytes = item.completedText?.utf8.count ?? item.accumulatedDelta.utf8.count
        let projectedUTF8Bytes = storedTextUTF8Bytes - replacedUTF8Bytes + text.utf8.count
        try validateStoredTextUTF8Bytes(projectedUTF8Bytes)
        item.accumulatedDelta.removeAll(keepingCapacity: false)
        item.completedText = text
        storedTextUTF8Bytes = projectedUTF8Bytes
        agentMessageTextsByItemID[itemID] = item
    }

    private func validateStoredTextUTF8Bytes(_ projectedUTF8Bytes: Int) throws {
        guard projectedUTF8Bytes <= CodexAppServerProtocolLimits.maximumStoredTextUTF8Bytes else {
            throw CodexAppServerParsingError.resourceLimitExceeded(.storedTextUTF8Bytes)
        }
    }

    private func finalTextSnapshot() -> String {
        var result = ""
        result.reserveCapacity(storedTextUTF8Bytes)
        for itemID in agentMessageItemIDs {
            if let text = agentMessageTextsByItemID[itemID]?.resolved { result.append(text) }
        }
        return result
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
        let completedText: String? = if case .agentMessage = kind {
            item["text"] as? String
        } else {
            nil
        }
        return .itemCompleted(
            id: id,
            kind: kind,
            completedText: completedText,
            providerEventType: method,
        )
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

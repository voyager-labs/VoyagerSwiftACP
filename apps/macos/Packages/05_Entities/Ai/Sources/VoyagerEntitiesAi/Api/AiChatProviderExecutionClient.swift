// swiftlint:disable file_length
import ComposableArchitecture
import Foundation

public enum AiChatProviderExecutionClientError: Error, Equatable, Sendable {
    case missingCredential(AiProvider)
    case invalidCredential(provider: AiProvider, expected: ProviderAuthMethod)
    case unsupportedProvider(AiProvider)
    case loweringFailed(AiChatProviderRequestLoweringError)
}

public enum AiChatProviderExecutionEvent: Equatable, Sendable {
    case requestPrepared(AiChatProviderRequestPayload)
    case started(context: AiChatRequestContextSnapshot)
    case delta(context: AiChatRequestContextSnapshot, text: String)
    case final(response: AiChatResponse)
    case failed(context: AiChatRequestContextSnapshot, reason: AiChatExecutionFailure)
}

public struct AiChatProviderExecutionClient: Sendable {
    public var execute: @Sendable (AiChatRequest, StoredCredentialPayload?) throws
        -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>

    public nonisolated init(
        execute: @escaping @Sendable (AiChatRequest, StoredCredentialPayload?) throws
            -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error>
    ) {
        self.execute = execute
    }
}

extension AiChatProviderExecutionClient: DependencyKey {
    public nonisolated static var liveValue: AiChatProviderExecutionClient {
        live()
    }

    public nonisolated static var testValue: AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(
            execute: { request, credential in
                let result = try AiChatProviderPreflight.prepare(request, credential: credential)
                return preparedStream(result.payload)
            }
        )
    }

    public nonisolated static var previewValue: AiChatProviderExecutionClient {
        testValue
    }
}

public extension DependencyValues {
    nonisolated var aiChatProviderExecutionClient: AiChatProviderExecutionClient {
        get { self[AiChatProviderExecutionClient.self] }
        set { self[AiChatProviderExecutionClient.self] = newValue }
    }
}

public extension AiChatProviderExecutionClient {
    nonisolated static func live(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) }
    ) -> AiChatProviderExecutionClient {
        live(session: session, now: now, codexExecutor: executeCodexCLI)
    }

    internal nonisolated static func live(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) },
        // swiftlint:disable:next line_length
        codexExecutor: @escaping @Sendable (_ model: String, _ prompt: String, _ credential: OAuthCredentialFile, _ onDelta: @escaping @Sendable (String) -> Void) async throws -> String
    ) -> AiChatProviderExecutionClient {
        AiChatProviderExecutionClient(
            execute: { request, credential in
                let result: AiChatProviderPreflightResult
                do {
                    result = try AiChatProviderPreflight.prepare(request, credential: credential)
                } catch let error as AiChatProviderPreflightError {
                    throw mapPreflightError(error)
                }

                switch result.payload.provider {
                case .openai:
                    return openAIStream(
                        context: request.context,
                        preflight: result,
                        session: session,
                        now: now
                    )
                case .anthropic:
                    return anthropicStream(
                        context: request.context,
                        preflight: result,
                        session: session,
                        now: now
                    )
                case .chatgptCodex:
                    return codexStream(
                        context: request.context,
                        preflight: result,
                        now: now,
                        executor: codexExecutor
                    )
                }
            }
        )
    }
}

private extension AiChatProviderExecutionClient {
    static func mapPreflightError(_ error: AiChatProviderPreflightError) -> AiChatProviderExecutionClientError {
        switch error {
        case let .missingCredential(provider):
            return .missingCredential(provider)
        case let .invalidCredential(provider, expected):
            return .invalidCredential(provider: provider, expected: expected)
        case let .loweringFailed(error):
            return .loweringFailed(error)
        }
    }

    static func preparedStream(
        _ payload: AiChatProviderRequestPayload
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.requestPrepared(payload))
            continuation.finish()
        }
    }

    // swiftlint:disable:next function_body_length
    static func openAIStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(context: context))

                do {
                    let request = try makeOpenAIRequest(payload: preflight.payload, credential: preflight.credential)
                    if usesCustomURLProtocol(session) {
                        try await consumeBufferedOpenAIResponse(
                            request: request,
                            session: session,
                            context: context,
                            now: now,
                            continuation: continuation
                        )
                        continuation.finish()
                        return
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    let httpResponse = try httpResponse(from: response)
                    try await validateStreamingHTTPStatus(httpResponse.statusCode, bytes: bytes)

                    let finalText: String?
                    if isEventStream(httpResponse) {
                        // swiftlint:disable:next line_length
                        finalText = try await consumeOpenAISSE(bytes.lines, context: context, continuation: continuation)
                    } else {
                        let data = try await collectData(bytes)
                        let parsed = try parseOpenAIResponse(data: data, response: httpResponse)
                        for delta in parsed.deltas where !delta.isEmpty {
                            continuation.yield(.delta(context: context, text: delta))
                        }
                        finalText = parsed.finalText
                    }

                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    guard let finalText = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !finalText.isEmpty
                    else {
                        continuation.yield(.failed(context: context, reason: .invalidRequest))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.final(response: AiChatResponse(
                        context: context,
                        assistantMessage: AiChatMessage(role: .assistant, content: finalText),
                        completedAtMs: now()
                    )))
                } catch is CancellationError {
                    continuation.finish()
                    return
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                    return
                } catch let error as URLError {
                    continuation.yield(.failed(
                        context: context,
                        reason: AiChatProviderExecutionFailureMapper.map(mapURLSessionError(error))
                    ))
                } catch let error as AiHTTPError {
                    continuation.yield(.failed(
                        context: context,
                        reason: AiChatProviderExecutionFailureMapper.map(error)
                    ))
                } catch {
                    continuation.yield(.failed(context: context, reason: .unknown))
                }

                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func anthropicStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(context: context))

                do {
                    let request = try makeAnthropicRequest(payload: preflight.payload, credential: preflight.credential)
                    if usesCustomURLProtocol(session) {
                        try await consumeBufferedAnthropicResponse(
                            request: request,
                            session: session,
                            context: context,
                            now: now,
                            continuation: continuation
                        )
                        continuation.finish()
                        return
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    let httpResponse = try httpResponse(from: response)
                    try await validateStreamingHTTPStatus(httpResponse.statusCode, bytes: bytes)

                    let finalText: String?
                    if isEventStream(httpResponse) {
                        // swiftlint:disable:next line_length
                        finalText = try await consumeAnthropicSSE(bytes.lines, context: context, continuation: continuation)
                    } else {
                        let data = try await collectData(bytes)
                        let parsed = try parseAnthropicResponse(data: data, response: httpResponse)
                        for delta in parsed.deltas where !delta.isEmpty {
                            continuation.yield(.delta(context: context, text: delta))
                        }
                        finalText = parsed.finalText
                    }

                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    guard let finalText = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !finalText.isEmpty
                    else {
                        continuation.yield(.failed(context: context, reason: .invalidRequest))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.final(response: AiChatResponse(
                        context: context,
                        assistantMessage: AiChatMessage(role: .assistant, content: finalText),
                        completedAtMs: now()
                    )))
                } catch is CancellationError {
                    continuation.finish()
                    return
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                    return
                } catch let error as URLError {
                    continuation.yield(.failed(
                        context: context,
                        reason: AiChatProviderExecutionFailureMapper.map(mapURLSessionError(error))
                    ))
                } catch let error as AiHTTPError {
                    continuation.yield(.failed(
                        context: context,
                        reason: AiChatProviderExecutionFailureMapper.map(error)
                    ))
                } catch let error as AnthropicStreamParsingError {
                    continuation.yield(.failed(context: context, reason: error.failureReason))
                } catch {
                    continuation.yield(.failed(context: context, reason: .transportError))
                }

                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func codexStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        now: @escaping @Sendable () -> Int64,
        // swiftlint:disable:next line_length
        executor: @escaping @Sendable (_ model: String, _ prompt: String, _ credential: OAuthCredentialFile, _ onDelta: @escaping @Sendable (String) -> Void) async throws -> String
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(context: context))

                do {
                    let prompt = makeCodexPrompt(payload: preflight.payload)
                    let credential = try codexCredential(from: preflight.credential)
                    let finalText = try await executor(preflight.payload.rawModelID, prompt, credential) { delta in
                        guard !delta.isEmpty else { return }
                        continuation.yield(.delta(context: context, text: delta))
                    }
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    guard !finalText.isEmpty else {
                        continuation.yield(.failed(context: context, reason: .invalidRequest))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.final(response: AiChatResponse(
                        context: context,
                        assistantMessage: AiChatMessage(role: .assistant, content: finalText),
                        completedAtMs: now()
                    )))
                } catch is CancellationError {
                    continuation.finish()
                    return
                } catch let error as CodexCLIExecutionError {
                    continuation.yield(.failed(context: context, reason: error.failureReason))
                } catch {
                    continuation.yield(.failed(context: context, reason: .transportError))
                }

                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func makeOpenAIRequest(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential
    ) throws -> URLRequest {
        guard case let .apiKey(secret) = credential else {
            throw AiChatProviderExecutionClientError.invalidCredential(provider: .openai, expected: .apiKey)
        }
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw AiHTTPError.invalidURL("https://api.openai.com/v1/responses")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(OpenAIResponsesCreateRequest(payload: payload))
        return request
    }

    static func makeAnthropicRequest(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential
    ) throws -> URLRequest {
        guard case let .apiKey(secret) = credential else {
            throw AiChatProviderExecutionClientError.invalidCredential(provider: .anthropic, expected: .apiKey)
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AiHTTPError.invalidURL("https://api.anthropic.com/v1/messages")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(secret, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AnthropicMessagesCreateRequest(payload: payload))
        return request
    }

    static func makeCodexPrompt(payload: AiChatProviderRequestPayload) -> String {
        var sections: [String] = []

        // swiftlint:disable:next line_length
        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload.context.currentContext), !contextText.isEmpty {
            sections.append(contextText)
        }

        // swiftlint:disable:next line_length
        if let promptSummary = payload.context.promptSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !promptSummary.isEmpty {
            sections.append("Prompt summary:\n\(promptSummary)")
        }

        let conversation = payload.messages
            .map { message in
                let role: String
                switch message.role {
                case .system:
                    role = "System"
                case .user:
                    role = "User"
                case .assistant:
                    role = "Assistant"
                case .tool:
                    role = "Tool"
                }
                return "\(role):\n\(message.content)"
            }
            .joined(separator: "\n\n")

        if !conversation.isEmpty {
            sections.append("Conversation:\n\(conversation)")
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    // swiftlint:disable:next function_body_length
    static func executeCodexCLI(
        model: String,
        prompt: String,
        credential: OAuthCredentialFile,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-codex-\(UUID().uuidString).txt")
        let codexHomeURL = try makeCodexHome(credential: credential)
        let processState = CodexProcessState(cleanupURLs: [outputURL, codexHomeURL])

        defer { processState.cleanup() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                do {
                    let resolvedCommand = try resolveCodexCommand()
                    process.executableURL = resolvedCommand.executableURL
                    process.arguments = [
                        "exec",
                        "--json",
                        "--model",
                        model,
                        "--output-last-message",
                        outputURL.path,
                        prompt
                    ]
                    process.environment = codexProcessEnvironment(codexHomeURL: codexHomeURL)
                    process.currentDirectoryURL = codexWorkingDirectory()
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    let jsonLineParser = CodexJSONLineParser(onDelta: onDelta)
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    outputPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        jsonLineParser.append(data)
                    }

                    try process.run()
                    processState.set(process: process)

                    Task.detached {
                        process.waitUntilExit()
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        jsonLineParser.finish()
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                        guard processState.markCompleted() else { return }

                        guard process.terminationStatus == 0 else {
                            continuation.resume(throwing: CodexCLIExecutionError.nonZeroExit(errorOutput))
                            return
                        }

                        do {
                            let output = try String(contentsOf: outputURL, encoding: .utf8)
                            continuation.resume(returning: output)
                        } catch {
                            continuation.resume(throwing: CodexCLIExecutionError.outputMissing(errorOutput))
                        }
                    }
                } catch let error as CodexCLIExecutionError {
                    outputPipeCleanup(process.standardOutput)
                    if processState.markCompleted() {
                        continuation.resume(throwing: error)
                    }
                } catch {
                    outputPipeCleanup(process.standardOutput)
                    if processState.markCompleted() {
                        continuation.resume(throwing: CodexCLIExecutionError.launchFailed)
                    }
                }
            }
        } onCancel: {
            processState.cancel()
        }
    }

    static func outputPipeCleanup(_ output: Any?) {
        guard let pipe = output as? Pipe else { return }
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    static func resolveCodexCommand() throws -> (executableURL: URL, argumentsPrefix: [String]) {
        let fileManager = FileManager.default
        // swiftlint:disable:next line_length
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] where fileManager.isExecutableFile(atPath: path) {
            return (URL(fileURLWithPath: path), [])
        }
        throw CodexCLIExecutionError.launchFailed
    }

    static func codexCredential(from credential: AiChatProviderValidatedCredential) throws -> OAuthCredentialFile {
        guard case let .oauth(payload) = credential else {
            throw CodexCLIExecutionError.launchFailed
        }
        return payload
    }

    static func makeCodexHome(credential: OAuthCredentialFile) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-codex-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let auth = CodexCLIAuthFile(credential: credential)
        let data = try JSONEncoder().encode(auth)
        let authURL = directory.appendingPathComponent("auth.json")
        let temporaryAuthURL = directory.appendingPathComponent("auth.json.tmp")
        try data.write(to: temporaryAuthURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryAuthURL.path)
        try FileManager.default.moveItem(at: temporaryAuthURL, to: authURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
        return directory
    }

    static func codexProcessEnvironment(codexHomeURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(defaultPath):\(path)"
        } else {
            environment["PATH"] = defaultPath
        }
        environment["CODEX_HOME"] = codexHomeURL.path
        return environment
    }

    static func codexWorkingDirectory() -> URL? {
        if let projectRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"], !projectRoot.isEmpty {
            return URL(fileURLWithPath: projectRoot)
        }
        return nil
    }

    static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AiHTTPError.networkError("Non-HTTP response")
        }
        return httpResponse
    }

    static func validateHTTPStatus(_ statusCode: Int, data: Data) throws {
        guard (200 ... 299).contains(statusCode) else {
            throw AiHTTPError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    static func parseOpenAIResponse(data: Data, response: HTTPURLResponse) throws -> ParsedOpenAIResponse {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") || looksLikeSSE(data) {
            return try parseOpenAISSE(data: data)
        }
        return try parseOpenAIFinalJSON(data: data)
    }

    static func looksLikeSSE(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("data:") && text.contains("response.")
    }

    static func parseOpenAISSE(data: Data) throws -> ParsedOpenAIResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AiHTTPError.networkError("OpenAI stream was not valid UTF-8.")
        }

        var deltas: [String] = []
        var finalText: String?

        for payload in ssePayloads(from: text) {
            guard payload != "[DONE]" else { continue }

            let event = try JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: Data(payload.utf8))
            switch event.type {
            case "response.output_text.delta":
                if let delta = event.delta, !delta.isEmpty {
                    deltas.append(delta)
                }
            case "response.output_text.done":
                if let text = event.text, !text.isEmpty {
                    finalText = text
                }
            case "response.completed":
                if let completedText = event.resolvedText, !completedText.isEmpty {
                    finalText = completedText
                }
            default:
                continue
            }
        }

        return ParsedOpenAIResponse(
            deltas: deltas,
            finalText: finalText ?? (deltas.isEmpty ? nil : deltas.joined())
        )
    }

    static func parseOpenAIFinalJSON(data: Data) throws -> ParsedOpenAIResponse {
        let response = try JSONDecoder().decode(OpenAIResponsesFinalResponse.self, from: data)
        return ParsedOpenAIResponse(deltas: [], finalText: response.resolvedText)
    }

    static func parseAnthropicResponse(data: Data, response: HTTPURLResponse) throws -> ParsedAnthropicResponse {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") || looksLikeAnthropicSSE(data) {
            return try parseAnthropicSSE(data: data)
        }
        return try parseAnthropicFinalJSON(data: data)
    }

    static func looksLikeAnthropicSSE(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("event: message_start") || text.contains("content_block_delta")
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func parseAnthropicSSE(data: Data) throws -> ParsedAnthropicResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AiHTTPError.networkError("Anthropic stream was not valid UTF-8.")
        }

        var deltas: [String] = []
        var finalText: String?
        let decoder = JSONDecoder()

        for payload in ssePayloads(from: text) {
            guard payload != "[DONE]" else { continue }

            let event: AnthropicStreamEvent
            do {
                event = try decoder.decode(AnthropicStreamEvent.self, from: Data(payload.utf8))
            } catch {
                throw AnthropicStreamParsingError.invalidPayload
            }

            switch event.type {
            case "content_block_start":
                if let text = event.contentBlock?.text, !text.isEmpty {
                    deltas.append(text)
                }
            case "content_block_delta":
                if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                    deltas.append(text)
                }
            case "message_delta":
                continue
            case "message_stop":
                if let completedText = event.message?.resolvedText, !completedText.isEmpty {
                    finalText = completedText
                }
            case "error":
                throw AnthropicStreamParsingError.provider(event.error)
            default:
                continue
            }
        }

        return ParsedAnthropicResponse(
            deltas: deltas,
            finalText: finalText ?? (deltas.isEmpty ? nil : deltas.joined())
        )
    }

    static func parseAnthropicFinalJSON(data: Data) throws -> ParsedAnthropicResponse {
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        return ParsedAnthropicResponse(deltas: [], finalText: response.resolvedText)
    }

    static func ssePayloads(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { chunk in
                let dataLines = chunk
                    .components(separatedBy: "\n")
                    .filter { $0.hasPrefix("data:") }
                    .map { line in
                        String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                    }
                guard !dataLines.isEmpty else { return nil }
                return dataLines.joined(separator: "\n")
            }
    }

    static func usesCustomURLProtocol(_ session: URLSession) -> Bool {
        session.configuration.protocolClasses?.isEmpty == false
    }

    static func consumeBufferedOpenAIResponse(
        request: URLRequest,
        session: URLSession,
        context: AiChatRequestContextSnapshot,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    ) async throws {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(from: response)
        try validateHTTPStatus(httpResponse.statusCode, data: data)
        let parsed = try parseOpenAIResponse(data: data, response: httpResponse)
        for delta in parsed.deltas where !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }
        try yieldFinalResponse(parsed.finalText, context: context, now: now, continuation: continuation)
    }

    static func consumeBufferedAnthropicResponse(
        request: URLRequest,
        session: URLSession,
        context: AiChatRequestContextSnapshot,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    ) async throws {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(from: response)
        try validateHTTPStatus(httpResponse.statusCode, data: data)
        let parsed = try parseAnthropicResponse(data: data, response: httpResponse)
        for delta in parsed.deltas where !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }
        try yieldFinalResponse(parsed.finalText, context: context, now: now, continuation: continuation)
    }

    static func yieldFinalResponse(
        _ text: String?,
        context: AiChatRequestContextSnapshot,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    ) throws {
        guard let finalText = text?.trimmingCharacters(in: .whitespacesAndNewlines), !finalText.isEmpty else {
            continuation.yield(.failed(context: context, reason: .invalidRequest))
            return
        }
        continuation.yield(.final(response: AiChatResponse(
            context: context,
            assistantMessage: AiChatMessage(role: .assistant, content: finalText),
            completedAtMs: now()
        )))
    }

    static func validateStreamingHTTPStatus(_ statusCode: Int, bytes: URLSession.AsyncBytes) async throws {
        guard (200 ... 299).contains(statusCode) else {
            let data = try await collectData(bytes)
            throw AiHTTPError.httpError(
                statusCode: statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    static func collectData(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    static func isEventStream(_ response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        return contentType.contains("text/event-stream")
    }

    static func consumeOpenAISSE<Lines: AsyncSequence>(
        _ lines: Lines,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    ) async throws -> String? where Lines.Element == String {
        var accumulator = SSEPayloadAccumulator()
        var deltas: [String] = []
        var finalText: String?

        for try await line in lines {
            try Task.checkCancellation()
            for payload in accumulator.consume(line) {
                // swiftlint:disable:next line_length
                if let delta = try consumeOpenAIPayload(payload, deltas: &deltas, finalText: &finalText), !delta.isEmpty {
                    continuation.yield(.delta(context: context, text: delta))
                }
            }
        }

        if let payload = accumulator.finish(),
           let delta = try consumeOpenAIPayload(payload, deltas: &deltas, finalText: &finalText),
           !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }

        return finalText ?? (deltas.isEmpty ? nil : deltas.joined())
    }

    static func consumeOpenAIPayload(
        _ payload: String,
        deltas: inout [String],
        finalText: inout String?
    ) throws -> String? {
        guard payload != "[DONE]" else { return nil }
        let event = try JSONDecoder().decode(OpenAIResponsesStreamEvent.self, from: Data(payload.utf8))
        switch event.type {
        case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
                deltas.append(delta)
                return delta
            }
        case "response.output_text.done":
            if let text = event.text, !text.isEmpty {
                finalText = text
            }
        case "response.completed":
            if let completedText = event.resolvedText, !completedText.isEmpty {
                finalText = completedText
            }
        default:
            break
        }
        return nil
    }

    static func consumeAnthropicSSE<Lines: AsyncSequence>(
        _ lines: Lines,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation
    ) async throws -> String? where Lines.Element == String {
        var accumulator = SSEPayloadAccumulator()
        var deltas: [String] = []
        var finalText: String?
        let decoder = JSONDecoder()

        for try await line in lines {
            try Task.checkCancellation()
            for payload in accumulator.consume(line) {
                if let delta = try consumeAnthropicPayload(
                    payload,
                    decoder: decoder,
                    deltas: &deltas,
                    finalText: &finalText
                ), !delta.isEmpty {
                    continuation.yield(.delta(context: context, text: delta))
                }
            }
        }

        if let payload = accumulator.finish(),
           let delta = try consumeAnthropicPayload(
            payload,
            decoder: decoder,
            deltas: &deltas,
            finalText: &finalText
           ), !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }

        return finalText ?? (deltas.isEmpty ? nil : deltas.joined())
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func consumeAnthropicPayload(
        _ payload: String,
        decoder: JSONDecoder,
        deltas: inout [String],
        finalText: inout String?
    ) throws -> String? {
        guard payload != "[DONE]" else { return nil }
        let event: AnthropicStreamEvent
        do {
            event = try decoder.decode(AnthropicStreamEvent.self, from: Data(payload.utf8))
        } catch {
            throw AnthropicStreamParsingError.invalidPayload
        }

        switch event.type {
        case "content_block_start":
            if let text = event.contentBlock?.text, !text.isEmpty {
                deltas.append(text)
                return text
            }
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                deltas.append(text)
                return text
            }
        case "message_delta":
            break
        case "message_stop":
            if let completedText = event.message?.resolvedText, !completedText.isEmpty {
                finalText = completedText
            }
        case "error":
            throw AnthropicStreamParsingError.provider(event.error)
        default:
            break
        }
        return nil
    }

    static func mapURLSessionError(_ error: URLError) -> AiHTTPError {
        let description = error.localizedDescription.lowercased()
        if description.contains("timed out") {
            return .timeout
        }

        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        // swiftlint:disable:next line_length
        case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .cannotLoadFromNetwork:
            return .networkError("network")
        default:
            return .networkError(error.localizedDescription)
        }
    }

    nonisolated static func currentTimeMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }
}

private struct SSEPayloadAccumulator {
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

private final class CodexProcessState: @unchecked Sendable {
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

private final class CodexJSONLineParser: @unchecked Sendable {
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
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        guard let event = try? JSONDecoder().decode(CodexJSONEvent.self, from: data),
              let delta = event.agentMessageDelta,
              !delta.isEmpty
        else { return }
        onDelta(delta)
    }
}

private struct CodexJSONEvent: Decodable, Sendable {
    let type: String?
    let method: String?
    let item: CodexJSONItem?
    let params: CodexJSONParams?
    let delta: String?

    var agentMessageDelta: String? {
        if method == "item/agentMessage/delta" {
            return params?.delta ?? delta
        }
        if type == "item.delta", item?.type == "agent_message" {
            return item?.text ?? delta
        }
        return nil
    }
}

private struct CodexJSONParams: Decodable, Sendable {
    let delta: String?
}

private struct CodexJSONItem: Decodable, Sendable {
    let type: String?
    let text: String?
}

private struct CodexCLIAuthFile: Encodable, Sendable {
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

private struct CodexCLIAuthTokens: Encodable, Sendable {
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

private enum CodexCLIExecutionError: Error, Equatable, Sendable {
    case launchFailed
    case outputMissing(String)
    case nonZeroExit(String)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .launchFailed:
            return .cliUnavailable
        case let .outputMissing(message), let .nonZeroExit(message):
            let lowered = message.lowercased()
            if lowered.contains("auth") || lowered.contains("login") || lowered.contains("unauthorized") {
                return .authentication
            }
            if lowered.contains("credit")
                || lowered.contains("quota")
                || lowered.contains("billing")
                || lowered.contains("balance")
                || lowered.contains("payment") {
                return .quotaExceeded
            }
            if lowered.contains("rate limit") || lowered.contains("too many requests") {
                return .rateLimited
            }
            if lowered.contains("model") && (lowered.contains("not found") || lowered.contains("unknown")) {
                return .modelUnavailable
            }
            return .invalidRequest
        }
    }
}

private struct ParsedOpenAIResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

private struct ParsedAnthropicResponse: Equatable, Sendable {
    let deltas: [String]
    let finalText: String?
}

private struct OpenAIResponsesCreateRequest: Encodable, Sendable {
    let model: String
    let input: [OpenAIResponsesInputItem]
    let reasoning: OpenAIResponsesReasoning?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        input = Self.makeInput(from: payload)
        reasoning = OpenAIResponsesReasoning(payload: payload.thinking)
        stream = true
    }

    private static func makeInput(from payload: AiChatProviderRequestPayload) -> [OpenAIResponsesInputItem] {
        var items: [OpenAIResponsesInputItem] = []

        // swiftlint:disable:next line_length
        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload.context.currentContext), !contextText.isEmpty {
            items.append(.init(role: .developer, text: contextText))
        }

        items.append(contentsOf: payload.messages.map {
            OpenAIResponsesInputItem(role: .init(messageRole: $0.role), text: $0.content)
        })
        return items
    }
}

private struct OpenAIResponsesInputItem: Encodable, Sendable {
    let role: Role
    let content: String

    init(role: Role, text: String) {
        self.role = role
        content = text
    }

    enum Role: String, Encodable, Sendable {
        case developer
        case user
        case assistant

        init(messageRole: AiChatMessageRole) {
            switch messageRole {
            case .system:
                self = .developer
            case .user, .tool:
                self = .user
            case .assistant:
                self = .assistant
            }
        }
    }
}

private struct OpenAIResponsesReasoning: Encodable, Sendable {
    let effort: String?
    let budgetTokens: Int?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .none:
            effort = "none"
            budgetTokens = nil
        case let .effort(value):
            effort = value.rawValue
            budgetTokens = nil
        case let .tokenBudget(value):
            effort = nil
            budgetTokens = value
        case let .adaptive(defaultEffort):
            effort = defaultEffort?.rawValue
            budgetTokens = nil
        case .disabled:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case effort
        case budgetTokens = "budget_tokens"
    }
}

private struct OpenAIResponsesFinalResponse: Decodable, Sendable {
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var resolvedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct OpenAIResponsesOutputItem: Decodable, Sendable {
    let content: [OpenAIResponsesOutputContent]?

    var assistantText: String? {
        let text = content?
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct OpenAIResponsesOutputContent: Decodable, Sendable {
    let type: String
    let text: String?
}

private struct OpenAIResponsesStreamEvent: Decodable, Sendable {
    let type: String
    let delta: String?
    let text: String?
    let outputText: String?
    let output: [OpenAIResponsesOutputItem]?
    let response: OpenAIResponsesFinalResponse?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case text
        case outputText = "output_text"
        case output
        case response
    }

    var resolvedText: String? {
        if let responseText = response?.resolvedText {
            return responseText
        }

        if let outputText, !outputText.isEmpty {
            return outputText
        }

        let text = output?
            .compactMap(\.assistantText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct AnthropicMessagesCreateRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let messages: [AnthropicMessageInput]
    let system: String?
    let thinking: AnthropicThinkingRequest?
    let outputConfig: AnthropicOutputConfig?
    let stream: Bool

    init(payload: AiChatProviderRequestPayload) {
        model = payload.rawModelID
        maxTokens = 4096
        system = AnthropicContextPromptBuilder.makeSystemPrompt(from: payload)
        messages = AnthropicMessageInput.makeMessages(from: payload.messages)
        thinking = AnthropicThinkingRequest(payload: payload.thinking)
        outputConfig = AnthropicOutputConfig(payload: payload.thinking)
        stream = true
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case thinking
        case outputConfig = "output_config"
        case stream
    }
}

private struct AnthropicMessageInput: Encodable, Sendable {
    let role: String
    let content: String

    static func makeMessages(from messages: [AiChatProviderMessage]) -> [AnthropicMessageInput] {
        messages.compactMap { message in
            switch message.role {
            case .user:
                return AnthropicMessageInput(role: "user", content: message.content)
            case .assistant:
                return AnthropicMessageInput(role: "assistant", content: message.content)
            case .system, .tool:
                return nil
            }
        }
    }
}

private struct AnthropicOutputConfig: Encodable, Sendable {
    let effort: String

    init?(payload: AiChatProviderThinkingPayload?) {
        guard case let .adaptive(defaultEffort) = payload,
              let defaultEffort
        else { return nil }
        effort = defaultEffort.rawValue
    }
}

private struct AnthropicThinkingRequest: Encodable, Sendable {
    let type: String
    let budgetTokens: Int?

    init?(payload: AiChatProviderThinkingPayload?) {
        guard let payload else { return nil }

        switch payload {
        case .disabled:
            type = "disabled"
            budgetTokens = nil
        case let .tokenBudget(value):
            type = "enabled"
            budgetTokens = value
        case .adaptive:
            type = "adaptive"
            budgetTokens = nil
        case .none, .effort:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

private struct AnthropicMessageResponse: Decodable, Sendable {
    let content: [AnthropicContentBlock]

    var resolvedText: String? {
        let text = content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

private struct AnthropicContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
}

private struct AnthropicStreamEvent: Decodable, Sendable {
    let type: String
    let delta: AnthropicStreamDelta?
    let message: AnthropicMessageResponse?
    let contentBlock: AnthropicContentBlock?
    let error: AnthropicStreamError?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case message
        case contentBlock = "content_block"
        case error
    }
}

private struct AnthropicStreamError: Decodable, Sendable, Equatable {
    let type: String?
    let message: String?
}

private enum AnthropicStreamParsingError: Error, Equatable {
    case invalidPayload
    case provider(AnthropicStreamError?)

    var failureReason: AiChatExecutionFailure {
        switch self {
        case .invalidPayload:
            return .invalidRequest
        case let .provider(error):
            switch error?.type {
            case "authentication_error", "permission_error":
                return .authentication
            case "not_found_error":
                return .modelUnavailable
            case "invalid_request_error":
                return .invalidRequest
            case "overloaded_error", "api_error":
                return .network
            case "rate_limit_error":
                return .rateLimited
            default:
                if let message = error?.message?.lowercased(),
                   message.contains("credit") || message.contains("quota") || message.contains("billing")
                    || message.contains("balance") || message.contains("payment") {
                    return .quotaExceeded
                }
                return .invalidRequest
            }
        }
    }
}

private struct AnthropicStreamDelta: Decodable, Sendable {
    let type: String?
    let text: String?
}

private enum OpenAIContextPromptBuilder {
    static func makePrompt(from context: AiChatCurrentContextSnapshot) -> String? {
        var lines: [String] = []

        if let summary = context.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("Current context summary: \(summary)")
        }
        if !context.references.isEmpty {
            lines.append("References:")
            lines.append(contentsOf: context.references.map(makeReferenceLine))
        }
        if !context.items.isEmpty {
            lines.append("Items:")
            lines.append(contentsOf: context.items.map(makeItemLine))
        }
        if !context.attachments.isEmpty {
            lines.append("Attachments:")
            lines.append(contentsOf: context.attachments.map(makeAttachmentLine))
        }

        guard !lines.isEmpty else { return nil }
        lines.append("Use this context when answering the user.")
        return lines.joined(separator: "\n")
    }

    static func makeReferenceLine(_ reference: AiChatContextReference) -> String {
        let title = reference.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? reference.identifier : title
        return "- [\(reference.kind.rawValue)] \(resolved)"
    }

    static func makeItemLine(_ item: AiChatContextItem) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? item.identifier : title
        return "- [\(item.kind.rawValue)] \(resolved)"
    }

    static func makeAttachmentLine(_ attachment: AiChatContextAttachment) -> String {
        let title = attachment.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = title.isEmpty ? attachment.identifier : title
        return "- \(resolved)"
    }
}

private enum AnthropicContextPromptBuilder {
    static func makeSystemPrompt(from payload: AiChatProviderRequestPayload) -> String? {
        var sections: [String] = []

        let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload.context.currentContext)
        if let contextText, !contextText.isEmpty {
            sections.append(contextText)
        }

        let systemMessages = payload.messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !systemMessages.isEmpty {
            sections.append(systemMessages.joined(separator: "\n\n"))
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }
}

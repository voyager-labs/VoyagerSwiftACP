import Foundation

extension AiChatProviderExecutionClient {
    static func makeOpenAIRequest(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential,
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(OpenAIResponsesCreateRequest(payload: payload))
        return request
    }

    static func makeAnthropicRequest(
        payload: AiChatProviderRequestPayload,
        credential: AiChatProviderValidatedCredential,
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AnthropicMessagesCreateRequest(payload: payload))
        return request
    }

    static func makeCodexPrompt(payload: AiChatProviderRequestPayload) -> String {
        var sections: [String] = []

        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload.context.currentContext),
           !contextText.isEmpty {
            sections.append(contextText)
        }

        if let promptSummary = payload.context.promptSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !promptSummary.isEmpty {
            sections.append("Prompt summary:\n\(promptSummary)")
        }

        let conversation = payload.messages
            .map { message in
                let role = switch message.role {
                case .system:
                    "System"
                case .user:
                    "User"
                case .assistant:
                    "Assistant"
                case .tool:
                    "Tool"
                }
                return "\(role):\n\(message.content)"
            }
            .joined(separator: "\n\n")

        if !conversation.isEmpty {
            sections.append("Conversation:\n\(conversation)")
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    static func executeCodexCLI(
        model: String,
        prompt: String,
        credential: OAuthCredentialFile,
        onDelta: @escaping @Sendable (String) -> Void,
    ) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voyager-codex-\(UUID().uuidString).txt")
        let codexHomeURL = try makeCodexHome(credential: credential)
        let processState = CodexProcessState(cleanupURLs: [outputURL, codexHomeURL])

        defer { processState.cleanup() }

        return try await withTaskCancellationHandler {
            try await runCodexProcess(CodexProcessRequest(
                model: model,
                prompt: prompt,
                outputURL: outputURL,
                codexHomeURL: codexHomeURL,
                processState: processState,
                onDelta: onDelta,
            ))
        } onCancel: {
            processState.cancel()
        }
    }

    static func runCodexProcess(_ request: CodexProcessRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            do {
                let processIO = try configureCodexProcess(process, request: request)
                try process.run()
                request.processState.set(process: process)
                waitForCodexProcess(
                    process,
                    outputURL: request.outputURL,
                    processState: request.processState,
                    processIO: processIO,
                    continuation: continuation,
                )
            } catch let error as CodexCLIExecutionError {
                outputPipeCleanup(process.standardOutput)
                resumeCodexLaunchFailure(error, processState: request.processState, continuation: continuation)
            } catch {
                outputPipeCleanup(process.standardOutput)
                resumeCodexLaunchFailure(.launchFailed, processState: request.processState, continuation: continuation)
            }
        }
    }

    static func configureCodexProcess(
        _ process: Process,
        request: CodexProcessRequest,
    ) throws -> CodexProcessIO {
        let resolvedCommand = try resolveCodexCommand()
        process.executableURL = resolvedCommand.executableURL
        process.arguments = codexArguments(model: request.model, outputURL: request.outputURL, prompt: request.prompt)
        process.environment = codexProcessEnvironment(codexHomeURL: request.codexHomeURL)
        process.currentDirectoryURL = codexWorkingDirectory()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let jsonLineParser = CodexJSONLineParser(onDelta: request.onDelta)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            jsonLineParser.append(data)
        }
        return CodexProcessIO(outputPipe: outputPipe, errorPipe: errorPipe, jsonLineParser: jsonLineParser)
    }

    static func codexArguments(model: String, outputURL: URL, prompt: String) -> [String] {
        [
            "exec",
            "--json",
            "--model",
            model,
            "--output-last-message",
            outputURL.path,
            prompt
        ]
    }

    static func waitForCodexProcess(
        _ process: Process,
        outputURL: URL,
        processState: CodexProcessState,
        processIO: CodexProcessIO,
        continuation: CheckedContinuation<String, Error>,
    ) {
        Task.detached {
            process.waitUntilExit()
            processIO.outputPipe.fileHandleForReading.readabilityHandler = nil
            processIO.jsonLineParser.finish()
            let errorData = processIO.errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            guard processState.markCompleted() else { return }
            resumeCodexProcessResult(
                process,
                outputURL: outputURL,
                errorOutput: errorOutput,
                continuation: continuation,
            )
        }
    }

    static func resumeCodexProcessResult(
        _ process: Process,
        outputURL: URL,
        errorOutput: String,
        continuation: CheckedContinuation<String, Error>,
    ) {
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

    static func resumeCodexLaunchFailure(
        _ error: CodexCLIExecutionError,
        processState: CodexProcessState,
        continuation: CheckedContinuation<String, Error>,
    ) {
        if processState.markCompleted() {
            continuation.resume(throwing: error)
        }
    }

    static func outputPipeCleanup(_ output: Any?) {
        guard let pipe = output as? Pipe else { return }
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    static func resolveCodexCommand() throws -> (executableURL: URL, argumentsPrefix: [String]) {
        let fileManager = FileManager.default
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            where fileManager.isExecutableFile(atPath: path) {
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

    struct CodexProcessRequest {
        var model: String
        var prompt: String
        var outputURL: URL
        var codexHomeURL: URL
        var processState: CodexProcessState
        var onDelta: @Sendable (String) -> Void
    }

    struct CodexProcessIO {
        var outputPipe: Pipe
        var errorPipe: Pipe
        var jsonLineParser: CodexJSONLineParser
    }
}

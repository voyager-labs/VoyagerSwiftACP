import Foundation

extension AiChatProviderExecutionClient {
    static let streamingExecutionRequestTimeout: TimeInterval = 300

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
        request.timeoutInterval = streamingExecutionRequestTimeout
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
        request.timeoutInterval = streamingExecutionRequestTimeout
        request.setValue(secret, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(AnthropicMessagesCreateRequest(payload: payload))
        return request
    }

    static func makeCodexPrompt(payload: AiChatProviderRequestPayload) -> String {
        var sections: [String] = []

        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload),
           !contextText.isEmpty
        {
            sections.append(contextText)
        }

        if let filesystemText = CodexContextPromptBuilder.makeFilesystemPrompt(
            from: payload.context.requestContext,
            workingDirectory: codexWorkingDirectory(),
        ), !filesystemText.isEmpty {
            sections.append(filesystemText)
        }

        if let promptSummary = payload.context.promptSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !promptSummary.isEmpty
        {
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
            sections.append([
                "Conversation transcript:",
                "Treat earlier Assistant and Tool entries as prior transcript history.",
                "Respond to the final User message only, continuing from that history.",
                conversation,
            ].joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    static func executeCodexCLI(
        model: String,
        prompt: String,
        thinking: AiChatProviderThinkingPayload?,
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
                thinking: thinking,
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
                waitForCodexProcess(
                    process,
                    outputURL: request.outputURL,
                    processState: request.processState,
                    processIO: processIO,
                    continuation: continuation,
                )
                try process.run()
                request.processState.set(process: process)
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
        process.arguments = codexArguments(
            model: request.model,
            outputURL: request.outputURL,
            prompt: request.prompt,
            thinking: request.thinking,
        )
        process.environment = codexProcessEnvironment(codexHomeURL: request.codexHomeURL)
        process.currentDirectoryURL = codexWorkingDirectory()

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let jsonLineParser = CodexJSONLineParser(onDelta: request.onDelta)
        let errorAccumulator = CodexPipeDataAccumulator()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            jsonLineParser.append(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            errorAccumulator.append(data)
        }
        return CodexProcessIO(
            outputPipe: outputPipe,
            errorPipe: errorPipe,
            jsonLineParser: jsonLineParser,
            errorAccumulator: errorAccumulator,
        )
    }

    static func codexArguments(
        model: String,
        outputURL: URL,
        prompt: String,
        thinking: AiChatProviderThinkingPayload?,
    ) -> [String] {
        var arguments = [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--model",
            model,
            "--output-last-message",
            outputURL.path,
        ]

        if let reasoningEffort = codexReasoningEffort(from: thinking) {
            arguments.append(contentsOf: ["-c", "model_reasoning_effort=\"\(reasoningEffort)\""])
        }

        arguments.append(prompt)
        return arguments
    }

    static func codexReasoningEffort(from thinking: AiChatProviderThinkingPayload?) -> String? {
        switch thinking {
        case .some(.none):
            "none"
        case let .some(.effort(value)), let .some(.adaptive(.some(value))):
            value.rawValue
        case nil, .some(.disabled), .some(.tokenBudget), .some(.adaptive(.none)):
            nil
        }
    }

    static func waitForCodexProcess(
        _ process: Process,
        outputURL: URL,
        processState: CodexProcessState,
        processIO: CodexProcessIO,
        continuation: CheckedContinuation<String, Error>,
    ) {
        process.terminationHandler = { terminatedProcess in
            terminatedProcess.terminationHandler = nil
            processIO.outputPipe.fileHandleForReading.readabilityHandler = nil
            processIO.errorPipe.fileHandleForReading.readabilityHandler = nil
            processIO.jsonLineParser.finish()
            let errorOutput = processIO.errorAccumulator.stringValue()

            guard processState.markCompleted() else { return }
            resumeCodexProcessResult(
                terminatedProcess,
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
            where fileManager.isExecutableFile(atPath: path)
        {
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
        // TODO(VOY-432): ProcessInfo 대신 Dotenv 사용 검토 — https://linear.app/voyager-fm/issue/VOY-432
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
        if let workingDirectory = ProcessInfo.processInfo.environment["VOYAGER_CODEX_WORKING_DIRECTORY"],
           !workingDirectory.isEmpty
        {
            return URL(fileURLWithPath: workingDirectory)
        }
        return nil
    }

    struct CodexProcessRequest {
        var model: String
        var prompt: String
        var thinking: AiChatProviderThinkingPayload?
        var outputURL: URL
        var codexHomeURL: URL
        var processState: CodexProcessState
        var onDelta: @Sendable (String) -> Void
    }

    struct CodexProcessIO {
        var outputPipe: Pipe
        var errorPipe: Pipe
        var jsonLineParser: CodexJSONLineParser
        var errorAccumulator: CodexPipeDataAccumulator
    }
}

private enum CodexContextPromptBuilder {
    private struct FilePathPair {
        let displayPath: String?
        let realPath: String?
    }

    private struct CodexPathEntry {
        let path: String
        let resolvesTo: String?
        let access: String
        let status: String
        let origin: String
        let kind: String
        let note: String

        var promptLines: [String] {
            var lines = [
                "  - path: \(path)",
                "    origin: \(origin)",
                "    kind: \(kind)",
                "    access: \(access)",
                "    status: \(status)",
            ]
            if let resolvesTo {
                lines.append("    resolves_to: \(resolvesTo)")
            }
            lines.append("    note: \(note)")
            return lines
        }
    }

    private struct CodexPathScopeInput {
        var providerKind: AiChatProviderNativeFileKind?
        var forcedReferenceOnly: Bool
        var hasWorkingDirectory: Bool
        var inScope: Bool
        var isSymlinkEscape: Bool
        var fileKind: AiChatContextItemKind
    }

    static func makeFilesystemPrompt(
        from requestContext: AiChatLockedRequestContextSnapshot,
        workingDirectory: URL?,
    ) -> String? {
        let normalizedWorkingDirectory = normalizedRealPathURL(workingDirectory)
        let entries = requestContext.parts.flatMap { part in
            makeEntries(from: part, workingDirectory: normalizedWorkingDirectory)
        }
        guard !entries.isEmpty else { return nil }

        var lines = [
            "codex_filesystem_references:",
            "  access_mode: path_scope_only",
            "  note: Treat these as referenced paths for Codex filesystem access. "
                + "Do not claim provider-native file transfer or extra directory grants for this request.",
        ]

        if let normalizedWorkingDirectory {
            lines.append("  working_directory: \(normalizedWorkingDirectory.path(percentEncoded: false))")
        } else {
            lines.append("  working_directory: unavailable")
            lines
                .append(
                    "  working_directory_note: Codex working directory is unavailable, "
                        + "so every path below is reference-only.",
                )
        }

        lines.append(contentsOf: entries.flatMap(\.promptLines))
        return lines.joined(separator: "\n")
    }

    private static func makeEntries(
        from part: AiChatLockedContextPartSnapshot,
        workingDirectory: URL?,
    ) -> [CodexPathEntry] {
        switch part.resolution {
        case let .providerNativeFile(kind, _, metadata):
            let displayPath = preferredDisplayPath(part: part, metadata: metadata)
            return [
                makeEntry(
                    paths: FilePathPair(
                        displayPath: displayPath,
                        realPath: preferredRealPath(part: part, metadata: metadata),
                    ),
                    fileKind: part.fileKind,
                    providerKind: kind,
                    originLabel: originLabel(for: part.source),
                    workingDirectory: workingDirectory,
                ),
            ]

        case let .referenceOnly(metadata):
            let displayPath = preferredDisplayPath(part: part, metadata: metadata)
            return [
                makeEntry(
                    paths: FilePathPair(
                        displayPath: displayPath,
                        realPath: preferredRealPath(part: part, metadata: metadata),
                    ),
                    fileKind: part.fileKind,
                    providerKind: nil,
                    originLabel: originLabel(for: part.source),
                    workingDirectory: workingDirectory,
                    forcedReferenceOnly: true,
                ),
            ]

        case let .collectionPathList(paths, _):
            return paths.map { rawPath in
                makeEntry(
                    paths: FilePathPair(
                        displayPath: rawPath,
                        realPath: normalizedRealPath(from: rawPath),
                    ),
                    fileKind: .attachment,
                    providerKind: .codexPathScope,
                    originLabel: "collection member",
                    workingDirectory: workingDirectory,
                )
            }

        case .inlineText, .partialText, .failure:
            return []
        }
    }

    private static func makeEntry(
        paths: FilePathPair,
        fileKind: AiChatContextItemKind,
        providerKind: AiChatProviderNativeFileKind?,
        originLabel: String,
        workingDirectory: URL?,
        forcedReferenceOnly: Bool = false,
    ) -> CodexPathEntry {
        let trimmedDisplayPath = normalizedNonEmpty(paths.displayPath)
        let trimmedRealPath = normalizedNonEmpty(paths.realPath)
        let resolvedDisplayURL = normalizedDisplayPathURL(from: trimmedDisplayPath)
        let resolvedRealURL = normalizedRealPathURL(from: trimmedRealPath)
        let effectiveRealURL = resolvedRealURL ?? resolvedDisplayURL
        let effectiveRealPath = effectiveRealURL?.path(percentEncoded: false) ?? trimmedRealPath

        let displayWithinWorkingDirectory = isWithinWorkingDirectory(
            resolvedDisplayURL,
            workingDirectory: workingDirectory,
        )
        let realWithinWorkingDirectory = isWithinWorkingDirectory(effectiveRealURL, workingDirectory: workingDirectory)
        let isSymlinkEscape = displayWithinWorkingDirectory && !realWithinWorkingDirectory

        let scopeInput = CodexPathScopeInput(
            providerKind: providerKind,
            forcedReferenceOnly: forcedReferenceOnly,
            hasWorkingDirectory: workingDirectory != nil,
            inScope: realWithinWorkingDirectory,
            isSymlinkEscape: isSymlinkEscape,
            fileKind: fileKind,
        )
        let status = statusLabel(scopeInput: scopeInput)
        let access = accessLabel(status: status)
        let note = noteLabel(scopeInput: scopeInput)

        let shouldRenderRealPath = status == "in_scope"
        let renderedPath = shouldRenderRealPath
            ? (effectiveRealPath ?? trimmedDisplayPath ?? "unavailable")
            : (trimmedDisplayPath ?? effectiveRealPath ?? "unavailable")
        return CodexPathEntry(
            path: renderedPath,
            resolvesTo: renderedPath == effectiveRealPath ? nil : effectiveRealPath,
            access: access,
            status: status,
            origin: originLabel,
            kind: fileKind.rawValue,
            note: note,
        )
    }

    private static func preferredDisplayPath(
        part: AiChatLockedContextPartSnapshot,
        metadata: [String: String],
    ) -> String? {
        [
            part.displayPath,
            metadata["displayPath"],
            metadata["path"],
            metadata["filePath"],
            part.canonicalPath,
        ].compactMap(normalizedNonEmpty).first
    }

    private static func preferredRealPath(
        part: AiChatLockedContextPartSnapshot,
        metadata: [String: String],
    ) -> String? {
        [
            part.canonicalPath,
            metadata["path"],
            metadata["filePath"],
            metadata["displayPath"],
            part.displayPath,
        ].lazy.compactMap(normalizedRealPath).first
    }

    private static func accessLabel(status: String) -> String {
        status == "in_scope"
            ? "referenced path (Codex filesystem access)"
            : "reference-only"
    }

    private static func statusLabel(scopeInput: CodexPathScopeInput) -> String {
        if !scopeInput.hasWorkingDirectory { return "reference_only" }
        if scopeInput.isSymlinkEscape { return "out_of_scope" }
        if !scopeInput.inScope { return "out_of_scope" }
        if scopeInput.forcedReferenceOnly { return "reference_only" }
        if scopeInput.providerKind != .codexPathScope { return "reference_only" }
        if scopeInput.providerKind == .image { return "reference_only" }
        return "in_scope"
    }

    private static func noteLabel(scopeInput: CodexPathScopeInput) -> String {
        if !scopeInput.hasWorkingDirectory {
            return "Codex working directory is unavailable for scope checks; treat this as a reference only."
        }
        if scopeInput.isSymlinkEscape {
            return "This workspace path resolves outside the Codex working directory (symlink escape); "
                + "do not assume Codex can read it."
        }
        if !scopeInput.inScope {
            return "This path resolves outside the Codex working directory; do not assume Codex can read it."
        }
        if scopeInput.forcedReferenceOnly {
            return "This path stays reference-only because the locked request context did not grant "
                + "Codex path-scope access for it."
        }
        if scopeInput.providerKind != .codexPathScope {
            return "This path stays reference-only because Codex uses filesystem references instead of "
                + "provider-native file transfer semantics."
        }
        if scopeInput.providerKind == .image {
            return "This image path is in scope, but images remain reference-only in this MVP because "
                + "no Codex image arguments are passed."
        }
        return "This path resolves inside the Codex working directory and may be read through Codex filesystem access."
    }

    private static func originLabel(for source: AiChatLockedContextPartSource) -> String {
        switch source {
        case .currentContext:
            "current context"
        case .attachment:
            "attachment"
        }
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func normalizedRealPath(from value: String?) -> String? {
        normalizedRealPathURL(from: value)?.path(percentEncoded: false)
    }

    private static func normalizedDisplayPathURL(from value: String?) -> URL? {
        guard let value = normalizedNonEmpty(value), value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private static func normalizedRealPathURL(_ value: URL?) -> URL? {
        guard let value else { return nil }
        return value.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func normalizedRealPathURL(from value: String?) -> URL? {
        guard let value = normalizedNonEmpty(value), value.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isWithinWorkingDirectory(_ candidate: URL?, workingDirectory: URL?) -> Bool {
        guard let candidate, let workingDirectory else { return false }
        let candidatePath = normalizedPathForComparison(candidate.path(percentEncoded: false))
        let workingDirectoryPath = normalizedPathForComparison(workingDirectory.path(percentEncoded: false))
        if candidatePath == workingDirectoryPath { return true }
        if workingDirectoryPath == "/" { return candidatePath.hasPrefix("/") }
        return candidatePath.hasPrefix(workingDirectoryPath + "/")
    }

    private static func normalizedPathForComparison(_ value: String) -> String {
        guard value.count > 1 else { return value }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }
}

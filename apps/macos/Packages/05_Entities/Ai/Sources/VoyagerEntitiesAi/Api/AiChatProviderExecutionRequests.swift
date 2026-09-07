import Foundation

enum CodexPathCanonicalizer {
    static func url(_ url: URL) -> URL {
        let resolvedPath = url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
        let canonicalPath = resolvedPath.count > 1 && resolvedPath.hasSuffix("/")
            ? String(resolvedPath.dropLast())
            : resolvedPath
        return URL(fileURLWithPath: canonicalPath, isDirectory: false)
    }

    static func path(_ url: URL) -> String {
        self.url(url).path(percentEncoded: false)
    }
}

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
        makeCodexPrompt(payload: payload, workingDirectory: codexSourceScopeRoot(payload: payload))
    }

    static func makeCodexPrompt(payload: AiChatProviderRequestPayload, workingDirectory: URL?) -> String {
        var sections: [String] = []

        if let contextText = OpenAIContextPromptBuilder.makePrompt(from: payload),
           !contextText.isEmpty
        {
            sections.append(contextText)
        }

        if let filesystemText = CodexContextPromptBuilder.makeFilesystemPrompt(
            from: payload.context.requestContext,
            workingDirectory: workingDirectory,
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

    static func codexReadablePaths(payload: AiChatProviderRequestPayload) -> [URL] {
        codexReadablePaths(payload: payload, workingDirectory: codexSourceScopeRoot(payload: payload))
    }

    static func codexReadablePaths(payload: AiChatProviderRequestPayload, workingDirectory: URL?) -> [URL] {
        CodexContextPromptBuilder.readablePaths(
            from: payload.context.requestContext,
            workingDirectory: workingDirectory,
        )
    }

    static func codexSourceScopeRoot(payload: AiChatProviderRequestPayload) -> URL? {
        payload.currentContext.references.lazy.compactMap { reference in
            guard reference.metadata["route"] == "folder",
                  let path = reference.metadata["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.hasPrefix("/")
            else {
                return nil
            }
            return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        }.first
    }

    static func codexReasoningEffort(from thinking: AiChatProviderThinkingPayload?) -> String? {
        switch thinking {
        case .some(AiChatProviderThinkingPayload.none):
            "none"
        case let .some(.effort(value)), let .some(.adaptive(.some(value))):
            value.rawValue
        case nil, .some(.disabled), .some(.tokenBudget), .some(.adaptive(.none)):
            nil
        }
    }

    static func codexProcessEnvironment(
        codexHomeURL: URL,
        parentEnvironment _: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [String: String] {
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return [
            "CODEX_HOME": codexHomeURL.path,
            "HOME": codexHomeURL.path,
            "LANG": "en_US.UTF-8",
            "PATH": defaultPath,
            "SHELL": "/bin/zsh",
            "TMPDIR": codexHomeURL.appendingPathComponent("session", isDirectory: true).path,
        ]
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
        let readableURL: URL?
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
            lines.append("  source_scope_root: \(normalizedWorkingDirectory.path(percentEncoded: false))")
        } else {
            lines.append("  source_scope_root: unavailable")
            lines
                .append(
                    "  source_scope_note: The configured source scope root is unavailable, "
                        + "so every path below is reference-only.",
                )
        }

        lines.append(contentsOf: entries.flatMap(\.promptLines))
        return lines.joined(separator: "\n")
    }

    static func readablePaths(
        from requestContext: AiChatLockedRequestContextSnapshot,
        workingDirectory: URL?,
    ) -> [URL] {
        let normalizedWorkingDirectory = normalizedRealPathURL(workingDirectory)
        var seen: Set<String> = []
        return requestContext.parts
            .flatMap { makeEntries(from: $0, workingDirectory: normalizedWorkingDirectory) }
            .compactMap(\.readableURL)
            .filter { seen.insert($0.path(percentEncoded: false)).inserted }
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
            readableURL: status == "in_scope" ? effectiveRealURL : nil,
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
            return "The configured source scope root is unavailable; treat this as a reference only."
        }
        if scopeInput.isSymlinkEscape {
            return "This workspace path resolves outside the configured source scope root (symlink escape); "
                + "do not assume Codex can read it."
        }
        if !scopeInput.inScope {
            return "This path resolves outside the configured source scope root; do not assume Codex can read it."
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
        return "This selected path resolves inside the configured source scope root and is readable by Codex."
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

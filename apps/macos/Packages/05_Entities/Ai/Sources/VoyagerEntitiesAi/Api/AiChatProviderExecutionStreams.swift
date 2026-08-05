import Foundation

extension AiChatProviderExecutionClient {
    static func mapPreflightError(_ error: AiChatProviderPreflightError) -> AiChatProviderExecutionClientError {
        switch error {
        case let .missingCredential(provider):
            .missingCredential(provider)
        case let .invalidCredential(provider, expected):
            .invalidCredential(provider: provider, expected: expected)
        case let .loweringFailed(error):
            .loweringFailed(error)
        }
    }

    static func preparedStream(
        _ payload: AiChatProviderRequestPayload,
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.requestPrepared(payload))
            continuation.finish()
        }
    }

    static func openAIStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64,
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await runOpenAIStream(
                    context: context,
                    preflight: preflight,
                    session: session,
                    now: now,
                    continuation: continuation,
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func anthropicStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64,
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await runAnthropicStream(
                    context: context,
                    preflight: preflight,
                    session: session,
                    now: now,
                    continuation: continuation,
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func runOpenAIStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async {
        continuation.yield(.started(context: context))
        do {
            let finalText = try await openAIFinalText(
                context: context,
                preflight: preflight,
                session: session,
                now: now,
                continuation: continuation,
            )
            finishProviderStream(finalText, context: context, now: now, continuation: continuation)
        } catch {
            finishOpenAIStreamFailure(error, context: context, continuation: continuation)
        }
        continuation.finish()
    }

    static func runAnthropicStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async {
        continuation.yield(.started(context: context))
        do {
            let finalText = try await anthropicFinalText(
                context: context,
                preflight: preflight,
                session: session,
                now: now,
                continuation: continuation,
            )
            finishProviderStream(finalText, context: context, now: now, continuation: continuation)
        } catch {
            finishAnthropicStreamFailure(error, context: context, continuation: continuation)
        }
        continuation.finish()
    }

    static func openAIFinalText(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now _: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        let request = try makeOpenAIRequest(payload: preflight.payload, credential: preflight.credential)
        if usesCustomURLProtocol(session) {
            return try await consumeBufferedOpenAIResponse(
                request: request,
                session: session,
                context: context,
                continuation: continuation,
            )
        }
        let (bytes, response) = try await session.bytes(for: request)
        let httpResponse = try httpResponse(from: response)
        try await validateStreamingHTTPStatus(httpResponse.statusCode, bytes: bytes)
        return try await streamedOpenAIFinalText(
            bytes: bytes,
            response: httpResponse,
            context: context,
            continuation: continuation,
        )
    }

    static func anthropicFinalText(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        session: URLSession,
        now _: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        let request = try makeAnthropicRequest(payload: preflight.payload, credential: preflight.credential)
        if usesCustomURLProtocol(session) {
            return try await consumeBufferedAnthropicResponse(
                request: request,
                session: session,
                context: context,
                continuation: continuation,
            )
        }
        return try await consumeAnthropicDataTaskStream(
            request: request,
            session: session,
            context: context,
            continuation: continuation,
        )
    }

    static func streamedOpenAIFinalText(
        bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        if isEventStream(response) {
            return try await consumeOpenAISSE(bytes.lines, context: context, continuation: continuation)
        }
        let data = try await collectData(bytes)
        let parsed = try parseOpenAIResponse(data: data, response: response)
        yieldDeltas(parsed.deltas, context: context, continuation: continuation)
        return parsed.finalText
    }

    static func streamedAnthropicFinalText(
        bytes: URLSession.AsyncBytes,
        response: HTTPURLResponse,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) async throws -> String? {
        if isEventStream(response) {
            return try await consumeAnthropicSSEBytes(bytes, context: context, continuation: continuation)
        }
        let data = try await collectData(bytes)
        let parsed = try parseAnthropicResponse(data: data, response: response)
        yieldDeltas(parsed.deltas, context: context, continuation: continuation)
        return parsed.finalText
    }

    static func yieldDeltas(
        _ deltas: [String],
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        for delta in deltas where !delta.isEmpty {
            continuation.yield(.delta(context: context, text: delta))
        }
    }

    static func finishProviderStream(
        _ finalText: String?,
        context: AiChatRequestContextSnapshot,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        guard !Task.isCancelled else { return }
        guard let finalText = finalText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !finalText.isEmpty
        else {
            continuation.yield(.failed(context: context, reason: .invalidRequest))
            return
        }
        continuation.yield(.final(response: AiChatResponse(
            context: context,
            assistantMessage: AiChatMessage(role: .assistant, content: finalText),
            completedAtMs: now(),
        )))
    }

    static func finishOpenAIStreamFailure(
        _ error: Error,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        switch error {
        case is CancellationError:
            return
        case let error as URLError where error.code == .cancelled:
            return
        case let error as URLError:
            NSLog(
                "[AiChatProviderExecution] OpenAI URL error requestID=%@ code=%ld description=%@",
                context.requestID.rawValue.uuidString,
                error.errorCode,
                error.localizedDescription,
            )
            continuation.yield(.failed(
                context: context,
                reason: AiChatProviderExecutionFailureMapper.map(mapURLSessionError(error)),
            ))
        case let error as AiHTTPError:
            NSLog(
                "[AiChatProviderExecution] OpenAI HTTP failure requestID=%@ reason=%@",
                context.requestID.rawValue.uuidString,
                providerHTTPLogReason(error),
            )
            continuation.yield(.failed(context: context, reason: AiChatProviderExecutionFailureMapper.map(error)))
        default:
            NSLog(
                "[AiChatProviderExecution] OpenAI unknown failure requestID=%@ error=%@",
                context.requestID.rawValue.uuidString,
                String(describing: error),
            )
            continuation.yield(.failed(context: context, reason: .unknown))
        }
    }

    static func finishAnthropicStreamFailure(
        _ error: Error,
        context: AiChatRequestContextSnapshot,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        switch error {
        case is CancellationError:
            return
        case let error as URLError where error.code == .cancelled:
            return
        case let error as URLError:
            continuation.yield(.failed(
                context: context,
                reason: AiChatProviderExecutionFailureMapper.map(mapURLSessionError(error)),
            ))
        case let error as AiHTTPError:
            continuation.yield(.failed(context: context, reason: AiChatProviderExecutionFailureMapper.map(error)))
        case let error as AnthropicStreamParsingError:
            continuation.yield(.failed(context: context, reason: error.failureReason))
        default:
            continuation.yield(.failed(context: context, reason: .transportError))
        }
    }

    static func codexStream(
        context: AiChatRequestContextSnapshot,
        preflight: AiChatProviderPreflightResult,
        now: @escaping @Sendable () -> Int64,
        executor: @escaping AiChatProviderCodexExecutor,
    ) -> AsyncThrowingStream<AiChatProviderExecutionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(context: context))
                let activityState = CodexActivityStateBox(context: context)

                do {
                    let workingDirectory = codexWorkingDirectory()
                    let prompt = makeCodexPrompt(payload: preflight.payload, workingDirectory: workingDirectory)
                    let readablePaths = codexReadablePaths(
                        payload: preflight.payload,
                        workingDirectory: workingDirectory,
                    )
                    let credential = try codexCredential(from: preflight.credential)
                    let finalText = try await executor(CodexExecutionRequest(
                        model: preflight.payload.rawModelID,
                        prompt: prompt,
                        thinking: preflight.payload.thinking,
                        readablePaths: readablePaths,
                        credential: credential,
                    )) { event in
                        for emission in activityState.consume(event) {
                            emitProviderPayload(emission, context: context, continuation: continuation)
                        }
                    }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    yieldCodexFinal(
                        context: context,
                        finalText: finalText,
                        now: now,
                        continuation: continuation,
                    )
                } catch is CancellationError {
                    continuation.finish()
                    return
                } catch let error as CodexCLIExecutionError {
                    yieldCodexError(context: context, error: error, continuation: continuation)
                } catch is CodexAppServerParsingError {
                    continuation.yield(.failed(context: context, reason: .invalidRequest))
                } catch {
                    yieldCodexUnknownError(context: context, error: error, continuation: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func yieldCodexFinal(
        context: AiChatRequestContextSnapshot,
        finalText: String,
        now: @escaping @Sendable () -> Int64,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
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
            completedAtMs: now(),
        )))
    }

    private static func yieldCodexError(
        context: AiChatRequestContextSnapshot,
        error: CodexCLIExecutionError,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        NSLog(
            "[AiChatProviderExecution] Codex CLI failure requestID=%@ reason=%@",
            context.requestID.rawValue.uuidString,
            codexLogReason(error),
        )
        continuation.yield(.failed(context: context, reason: error.failureReason))
    }

    private static func yieldCodexUnknownError(
        context: AiChatRequestContextSnapshot,
        error: Error,
        continuation: AsyncThrowingStream<AiChatProviderExecutionEvent, Error>.Continuation,
    ) {
        NSLog(
            "[AiChatProviderExecution] Codex unknown failure requestID=%@ error=%@",
            context.requestID.rawValue.uuidString,
            String(describing: error),
        )
        continuation.yield(.failed(context: context, reason: .transportError))
    }
}

private func providerHTTPLogReason(_ error: AiHTTPError) -> String {
    switch error {
    case let .httpError(statusCode, body):
        "httpError(status: \(statusCode), body: \(redactedProviderErrorBody(body)))"
    case let .networkError(description):
        "networkError(\(description))"
    case .timeout:
        "timeout"
    case .cancelled:
        "cancelled"
    case let .invalidURL(url):
        "invalidURL(\(url))"
    }
}

private func redactedProviderErrorBody(_ body: String) -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "empty" }
    let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
    return String(singleLine.prefix(1200))
}

private func codexLogReason(_ error: CodexCLIExecutionError) -> String {
    switch error {
    case .launchFailed:
        "launchFailed"
    case let .outputMissing(message):
        "outputMissing(\(redactedProviderErrorBody(message)))"
    case let .nonZeroExit(message):
        "nonZeroExit(\(redactedProviderErrorBody(message)))"
    case let .protocolFailure(reason):
        "protocolFailure(\(reason.rawValue))"
    }
}

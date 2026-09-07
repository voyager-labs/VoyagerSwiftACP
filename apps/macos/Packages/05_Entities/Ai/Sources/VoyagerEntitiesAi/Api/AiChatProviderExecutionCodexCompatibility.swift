import Foundation

extension CodexExecLiveComposition {
    func executeLegacy(
        request: CodexExecutionRequest,
        onEvent: @escaping @Sendable (CodexAppServerEvent) -> Void,
    ) async throws -> String {
        let preparedSession: URL
        do {
            preparedSession = try await legacySessionPreparer.prepare(codexHome: codexHome)
        } catch {
            throw CodexCLIExecutionError.launchFailed
        }
        let workingDirectory = request.workingDirectory ?? preparedSession

        let readiness: CodexExecReadiness
        do {
            readiness = try readinessProbe.check(
                executableURL: executableURL,
                environment: AiChatProviderExecutionClient.codexProcessEnvironment(codexHomeURL: codexHome),
            )
        } catch let error as CodexExecReadinessError {
            throw CodexCLIExecutionError.readinessFailed(error)
        } catch {
            throw CodexCLIExecutionError.launchFailed
        }

        let command = try CodexExecCommandBuilder.build(
            request: CodexExecCommandRequest(
                model: request.model,
                prompt: request.prompt,
                workingDirectory: workingDirectory,
                sandbox: .readOnly,
                primaryWritableRoot: workingDirectory,
                additionalWritableRoots: [],
                codexHome: codexHome,
                reasoningEffort: AiChatProviderExecutionClient.codexReasoningEffort(from: request.thinking),
                readablePaths: request.readablePaths,
                skipGitRepositoryCheck: request.workingDirectory != nil,
            ),
            executableURL: readiness.executableURL,
        )
        let receipt = try await controller.acquire(runID: request.runID, command: command)
        return try await withTaskCancellationHandler {
            try await consumeLegacy(receipt: receipt, onEvent: onEvent)
        } onCancel: {
            Task { await receipt.cancel() }
        }
    }
}

private func consumeLegacy(
    receipt: CodexExecProcessReceipt,
    onEvent: @escaping @Sendable (CodexAppServerEvent) -> Void,
) async throws -> String {
    let lifecycle = try await receipt.eventStream()
    let lifecycleTask = Task {
        do {
            for try await _ in lifecycle {}
        } catch {}
    }

    do {
        var eventStreamFailure: Error?
        do {
            for try await event in receipt.events {
                if let mapped = CodexExecCompatibilityMapper.map(event) {
                    onEvent(mapped)
                }
            }
        } catch {
            eventStreamFailure = error
        }
        let result: CodexExecTerminalResult
        do {
            result = try await receipt.terminalResult()
        } catch {
            lifecycleTask.cancel()
            throw eventStreamFailure ?? error
        }
        await lifecycleTask.value
        try throwLegacyEventStreamFailure(eventStreamFailure)
        guard result.outcome == .completed else {
            throw CodexCLIExecutionError.protocolFailure(
                legacyFailureReason(for: result),
            )
        }
        return result.finalAssistantText.value
    } catch is CancellationError {
        lifecycleTask.cancel()
        throw CancellationError()
    } catch let error as CodexCLIExecutionError {
        lifecycleTask.cancel()
        throw error
    } catch let error as CodexExecProcessFailure {
        lifecycleTask.cancel()
        throw CodexCLIExecutionError.protocolFailure(CodexExecLiveComposition.failureReason(for: error))
    } catch {
        lifecycleTask.cancel()
        throw CodexCLIExecutionError.protocolFailure(.transportError)
    }
}

private func throwLegacyEventStreamFailure(_ error: Error?) throws {
    if let error { throw error }
}

private func legacyFailureReason(for result: CodexExecTerminalResult) -> AiChatExecutionFailure {
    switch result.failure {
    case .none, .some(.terminalError):
        AiChatProviderExecutionClient.codexFailureReason(forCLIErrorOutput: result.diagnostics.stderr)
    case let .some(failure):
        CodexExecLiveComposition.failureReason(for: failure)
    }
}

private extension CodexExecLiveComposition {
    static func failureReason(for failure: CodexExecProcessFailure) -> AiChatExecutionFailure {
        switch failure {
        case .processFailed, .launchFailed:
            .cliUnavailable
        case .eofBeforeTerminal, .terminalError, .duplicateTerminal, .decoder, .eventBufferOverflow,
             .encodedEventBufferOverflow, .earlyEvent, .emptyThreadID, .eofBeforeHandshake:
            .transportError
        }
    }
}

enum CodexExecCompatibilityMapper {
    static func map(_ event: CodexExecDecodedEvent) -> CodexAppServerEvent? {
        let payload = event.payload
        switch event.type {
        case .turnStarted: return mapTurnStarted(payload, eventType: event.type.rawValue)
        case .turnCompleted, .turnFailed:
            return mapTurnCompleted(payload, eventType: event.type.rawValue, failed: event.type == .turnFailed)
        case .itemStarted:
            return mapItemStarted(payload, eventType: event.type.rawValue)
        case .itemCompleted:
            return mapItemCompleted(payload, eventType: event.type.rawValue)
        case .itemUpdated:
            guard let id = payload.itemID, let text = payload.text,
                  CodexExecItemType.isAgentMessage(payload.itemType)
            else { return nil }
            return .agentMessageDelta(itemID: id, delta: text)
        case .error:
            guard let turnID = payload.turnID else { return nil }
            return .error(turnID: turnID, willRetry: false, providerEventType: event.type.rawValue)
        case .threadStarted, .unknown:
            return nil
        }
    }

    private static func mapTurnStarted(_ payload: CodexExecEventPayload, eventType: String) -> CodexAppServerEvent? {
        guard let turnID = payload.turnID else { return nil }
        return .turnStarted(turnID: turnID, providerEventType: eventType)
    }

    private static func mapTurnCompleted(
        _ payload: CodexExecEventPayload,
        eventType: String,
        failed: Bool,
    ) -> CodexAppServerEvent? {
        guard let turnID = payload.turnID else { return nil }
        let status: CodexAppServerTurnStatus = failed || payload.status == "failed" ? .failed : .completed
        return .turnCompleted(
            turnID: turnID,
            status: status,
            failure: status == .failed ? .transportError : nil,
            providerEventType: eventType,
        )
    }

    private static func mapItemStarted(_ payload: CodexExecEventPayload, eventType: String) -> CodexAppServerEvent? {
        guard let id = payload.itemID, let kind = itemKind(payload.itemType) else { return nil }
        return .itemStarted(id: id, kind: kind, providerEventType: eventType)
    }

    private static func mapItemCompleted(_ payload: CodexExecEventPayload, eventType: String) -> CodexAppServerEvent? {
        guard let id = payload.itemID, let kind = itemKind(payload.itemType) else { return nil }
        let completedText = kind == .agentMessage(phase: nil) ? payload.text : nil
        return .itemCompleted(id: id, kind: kind, completedText: completedText, providerEventType: eventType)
    }

    private static func itemKind(_ value: String?) -> CodexAppServerItemKind? {
        switch value {
        case "reasoning": .reasoning
        case "webSearch", "web_search": .webSearch
        case "commandExecution", "command_execution": .commandExecution
        case "mcpToolCall", "mcp_tool_call": .mcpToolCall
        case let value where CodexExecItemType.isAgentMessage(value): .agentMessage(phase: nil)
        default: nil
        }
    }
}

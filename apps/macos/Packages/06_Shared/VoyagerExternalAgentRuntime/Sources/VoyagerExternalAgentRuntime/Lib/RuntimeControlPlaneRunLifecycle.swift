import Foundation

enum RuntimeTerminalEventPersistenceError: Error {
    case persistenceFailure
}

extension RuntimeControlPlane {
    private enum ProviderEventDisposition {
        case nonterminal
        case providerTerminal(RuntimeResult)
        case storedTerminal(RuntimeResult)
    }

    private enum ProviderStreamSource {
        case stream(AsyncThrowingStream<RuntimeEventEnvelope, any Error>)
        case storedTerminal(RuntimeResult)
    }

    func consume(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        if adapter.descriptor.capabilities.eventStream == .supported {
            return try await consumeEventStream(receipt, from: adapter, host: host)
        }
        return try await consumeTerminalResult(receipt, from: adapter, host: host)
    }

    private func consumeEventStream(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        let stream: AsyncThrowingStream<RuntimeEventEnvelope, any Error>
        switch try await providerEventStream(receipt, from: adapter, host: host) {
        case let .stream(providerStream):
            stream = providerStream
        case let .storedTerminal(terminal):
            return terminal
        }
        var iterator = stream.makeAsyncIterator()
        while true {
            let event: RuntimeEventEnvelope?
            do {
                event = try await iterator.next()
            } catch {
                if let terminal = try await persistedTerminalResult(host: host, runReference: receipt.runReference) {
                    return terminal
                }
                throw error
            }
            guard let event else { break }
            switch try await acceptProviderEvent(event, receipt: receipt, host: host) {
            case .nonterminal:
                continue
            case let .storedTerminal(terminal):
                return terminal
            case let .providerTerminal(terminal):
                return try await providerTerminalResult(
                    terminal,
                    receipt: receipt,
                    from: adapter,
                    host: host,
                )
            }
        }
        return try await consumeTerminalResult(receipt, from: adapter, host: host)
    }

    private func providerEventStream(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> ProviderStreamSource {
        do {
            return try await .stream(adapter.eventStream(for: receipt.runReference))
        } catch {
            if let terminal = try await persistedTerminalResult(host: host, runReference: receipt.runReference) {
                return .storedTerminal(terminal)
            }
            throw error
        }
    }

    private func providerTerminalResult(
        _ terminal: RuntimeResult,
        receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        guard adapter.descriptor.capabilities.terminalResult == .supported else { return terminal }
        let result: RuntimeResult
        do {
            result = try await adapter.terminalResult(for: receipt.runReference)
        } catch {
            if let terminal = try await persistedTerminalResult(host: host, runReference: receipt.runReference) {
                return terminal
            }
            throw error
        }
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        guard result.outcome == terminal.outcome else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return result
    }

    private func acceptProviderEvent(
        _ event: RuntimeEventEnvelope,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
    ) async throws -> ProviderEventDisposition {
        do {
            return try await acceptProviderEvent(event, host: host)
        } catch RuntimeHostError.persistenceFailure where providerTerminalOutcome(for: event) != nil {
            do {
                return try await acceptProviderEvent(event, host: host)
            } catch RuntimeHostError.persistenceFailure {
                throw RuntimeTerminalEventPersistenceError.persistenceFailure
            }
        } catch let error as RuntimeHostError {
            guard error == .malformedAdapterResponse,
                  isSameRunProviderEvent(event, receipt: receipt, host: host),
                  let terminal = try await persistedTerminalResult(host: host, runReference: receipt.runReference)
            else { throw error }
            return .storedTerminal(terminal)
        }
    }

    private func acceptProviderEvent(
        _ event: RuntimeEventEnvelope,
        host: ExternalAgentSessionReference,
    ) async throws -> ProviderEventDisposition {
        guard let terminal = try await accept(event, host: host, expectedSource: .provider) else {
            return .nonterminal
        }
        return .providerTerminal(terminal)
    }

    private func providerTerminalOutcome(for event: RuntimeEventEnvelope) -> RuntimeOutcome? {
        switch event.kind {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        default: nil
        }
    }

    private func isSameRunProviderEvent(
        _ event: RuntimeEventEnvelope,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
    ) -> Bool {
        event.source == .provider
            && event.externalAgentSessionReference == host
            && event.runReference == receipt.runReference
            && event.providerEventID.rawValue.isRuntimeBounded
            && event.idempotencyKey.rawValue.isRuntimeBounded
    }

    private func consumeTerminalResult(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        try require(.terminalResult, in: adapter.descriptor.capabilities)
        let result: RuntimeResult
        do {
            result = try await adapter.terminalResult(for: receipt.runReference)
        } catch {
            if let terminal = try await persistedTerminalResult(host: host, runReference: receipt.runReference) {
                return terminal
            }
            throw error
        }
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return result
    }

    func persistedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult? {
        try await mutateAfterPersistedTransitions { plane in
            plane.storedTerminalResult(host: host, runReference: runReference)
        }
    }

    func storedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) -> RuntimeResult? {
        guard let stored = sessions[host]?.stored,
              stored.runReference == runReference,
              let outcome = outcome(for: stored.projection)
        else { return nil }
        return RuntimeResult(
            runReference: runReference,
            outcome: outcome,
            artifactReferences: [],
        )
    }
}

extension RuntimeStoredSession {
    func matchesLaunchSnapshot(
        _ request: RuntimeLaunchRequest,
        descriptor: RuntimeAdapterDescriptor,
    ) -> Bool {
        runReference == request.runReference
            && adapterID == descriptor.id
            && providerNamespace == descriptor.providerNamespace
            && adapterVersion == descriptor.adapterVersion
            && providerBranch == descriptor.providerBranch
            && capabilitySnapshot == descriptor.capabilities
            && contextPolicy.hasSameExecutionContext(as: request.contextPolicy)
    }
}

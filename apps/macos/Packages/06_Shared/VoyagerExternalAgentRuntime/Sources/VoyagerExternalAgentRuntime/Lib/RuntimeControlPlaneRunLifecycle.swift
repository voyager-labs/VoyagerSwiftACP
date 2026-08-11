import Foundation

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
                if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
                    return terminal
                }
                throw error
            }
            guard let event else { break }
            if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
                return terminal
            }
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
            if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
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
        let result = try await adapter.terminalResult(for: receipt.runReference)
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return resultRespectingStoredTerminal(result, host: host)
    }

    private func acceptProviderEvent(
        _ event: RuntimeEventEnvelope,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
    ) async throws -> ProviderEventDisposition {
        do {
            guard let terminal = try await accept(event, host: host, expectedSource: .provider) else {
                return .nonterminal
            }
            return .providerTerminal(terminal)
        } catch let error as RuntimeHostError {
            guard error == .malformedAdapterResponse,
                  isSameRunProviderEvent(event, receipt: receipt, host: host),
                  let terminal = storedTerminalResult(host: host, runReference: receipt.runReference)
            else { throw error }
            return .storedTerminal(terminal)
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
            if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
                return terminal
            }
            throw error
        }
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return resultRespectingStoredTerminal(result, host: host)
    }

    func resultRespectingStoredTerminal(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
    ) -> RuntimeResult {
        guard let stored = sessions[host]?.stored,
              stored.runReference == result.runReference,
              let storedOutcome = outcome(for: stored.projection),
              storedOutcome != result.outcome
        else { return result }
        return RuntimeResult(
            runReference: result.runReference,
            outcome: storedOutcome,
            artifactReferences: [],
        )
    }

    private func storedTerminalResult(
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

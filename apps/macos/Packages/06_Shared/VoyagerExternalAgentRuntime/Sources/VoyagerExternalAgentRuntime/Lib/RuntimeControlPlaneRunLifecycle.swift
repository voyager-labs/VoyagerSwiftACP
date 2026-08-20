import Foundation

enum RuntimeTerminalEventPersistenceError: Error {
    case persistenceFailure
}

enum RuntimeProviderTerminalAdmissionError: Error {
    case rejected
}

extension RuntimeControlPlane {
    private enum ProviderEventDisposition {
        case nonterminal
        case rejectedTerminal
        case providerTerminal(RuntimeResult)
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
        return try await consumeTerminalResult(receipt, from: adapter)
    }

    private func consumeEventStream(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        let stream = try await providerEventStream(receipt, from: adapter)
        var iterator = stream.makeAsyncIterator()
        var rejectedTerminalEvidence = false
        while true {
            let event = try await iterator.next()
            guard let event else { break }
            switch try await acceptProviderEvent(event, receipt: receipt, host: host) {
            case .nonterminal:
                continue
            case .rejectedTerminal:
                rejectedTerminalEvidence = true
                continue
            case let .storedTerminal(terminal):
                return terminal
            case let .providerTerminal(terminal):
                return try await providerTerminalResult(
                    terminal,
                    receipt: receipt,
                    from: adapter,
                )
            }
        }
        if rejectedTerminalEvidence {
            throw RuntimeProviderTerminalAdmissionError.rejected
        }
        return try await consumeTerminalResult(receipt, from: adapter)
    }

    private func providerEventStream(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
    ) async throws -> AsyncThrowingStream<RuntimeEventEnvelope, any Error> {
        try await adapter.eventStream(for: receipt.runReference)
    }

    private func providerTerminalResult(
        _ terminal: RuntimeResult,
        receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
    ) async throws -> RuntimeResult {
        guard adapter.descriptor.capabilities.terminalResult == .supported else { return terminal }
        let result = try await adapter.terminalResult(for: receipt.runReference)
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
            let disposition = try await acceptProviderEvent(event, host: host)
            switch disposition {
            case .nonterminal where providerTerminalOutcome(for: event) != nil:
                return .rejectedTerminal
            case .nonterminal:
                return .nonterminal
            default:
                return disposition
            }
        } catch let error as RuntimeHostError {
            guard error == .malformedAdapterResponse,
                  let repaired = try await readRepairProviderTerminalConflict(
                      event,
                      receipt: receipt,
                      host: host,
                  )
            else { throw error }
            return repaired
        }
    }

    private func readRepairProviderTerminalConflict(
        _ event: RuntimeEventEnvelope,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
    ) async throws -> ProviderEventDisposition? {
        guard isSameRunProviderEvent(event, receipt: receipt, host: host),
              let terminal = try await readRepairPersistedTerminal(
                  host: host,
                  runReference: receipt.runReference,
              )
        else { return nil }
        return .storedTerminal(terminal)
    }

    func readRepairPersistedTerminal(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult? {
        // read-repair: adopt a committed persisted terminal only through the explicit conflict path.
        try await withPersistedState { plane, loaded in
            let current = plane.sessions[host]?.freshRunSnapshot()
            guard let adopted = plane.adoptingPersistedTerminal(
                host: host,
                runReference: runReference,
                expectedSession: plane.sessions[host],
                loaded: loaded,
            ) else {
                try Task.checkCancellation()
                return nil
            }
            let persisted = adopted.freshRunSnapshot()
            guard case .adoptPersisted = RuntimeFreshRunDecisionTable.decide(
                .persistConflict(persisted: persisted),
                on: current ?? persisted,
            ) else {
                try Task.checkCancellation()
                return nil
            }
            plane.sessions[host] = adopted
            try Task.checkCancellation()
            return plane.terminalResult(for: adopted.stored)
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
    ) async throws -> RuntimeResult {
        try require(.terminalResult, in: adapter.descriptor.capabilities)
        let result = try await adapter.terminalResult(for: receipt.runReference)
        guard result.runReference == receipt.runReference else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        return result
    }

    func persistedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult? {
        try await withPersistedState { plane, loaded in
            guard let adopted = plane.adoptingPersistedTerminal(
                host: host,
                runReference: runReference,
                expectedSession: plane.sessions[host],
                loaded: loaded,
            ) else {
                try Task.checkCancellation()
                return nil
            }
            plane.sessions[host] = adopted
            try Task.checkCancellation()
            return plane.terminalResult(for: adopted.stored)
        }
    }

    func storedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) -> RuntimeResult? {
        guard let stored = sessions[host]?.stored,
              stored.runReference == runReference
        else { return nil }
        return terminalResult(for: stored)
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
            && storedContext == RuntimeStoredContext(contextPolicy: request.contextPolicy)
    }
}

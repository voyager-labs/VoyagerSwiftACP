import Foundation

extension RuntimeControlPlane {
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
        do {
            stream = try await adapter.eventStream(for: receipt.runReference)
        } catch {
            if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
                return terminal
            }
            throw error
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
            if let terminal = try await accept(event, host: host, expectedSource: .provider) {
                guard adapter.descriptor.capabilities.terminalResult == .supported else {
                    return terminal
                }
                let result = try await adapter.terminalResult(for: receipt.runReference)
                guard result.runReference == receipt.runReference else {
                    throw RuntimeHostError.malformedAdapterResponse
                }
                return resultRespectingStoredTerminal(result, host: host)
            }
        }
        return try await consumeTerminalResult(receipt, from: adapter, host: host)
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

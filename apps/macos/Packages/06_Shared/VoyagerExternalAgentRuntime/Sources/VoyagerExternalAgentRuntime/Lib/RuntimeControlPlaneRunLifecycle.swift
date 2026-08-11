import Foundation

extension RuntimeControlPlane {
    func consume(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        if adapter.descriptor.capabilities.eventStream == .supported {
            do {
                let stream = try await adapter.eventStream(for: receipt.runReference)
                for try await event in stream {
                    if let terminal = try await accept(event, host: host, expectedSource: .provider) {
                        if adapter.descriptor.capabilities.terminalResult == .supported {
                            let result = try await adapter.terminalResult(for: receipt.runReference)
                            guard result.runReference == receipt.runReference else {
                                throw RuntimeHostError.malformedAdapterResponse
                            }
                            return resultRespectingStoredTerminal(result, host: host)
                        }
                        return terminal
                    }
                }
            } catch {
                if let terminal = storedTerminalResult(
                    host: host,
                    runReference: receipt.runReference,
                ) {
                    return terminal
                }
                throw error
            }
        }
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
        guard let projection = sessions[host]?.stored.projection,
              let storedOutcome = outcome(for: projection),
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
        guard let projection = sessions[host]?.stored.projection,
              let outcome = outcome(for: projection)
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

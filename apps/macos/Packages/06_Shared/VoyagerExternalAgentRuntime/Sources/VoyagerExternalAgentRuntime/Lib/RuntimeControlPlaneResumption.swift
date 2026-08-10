import Foundation

public extension RuntimeControlPlane {
    func resumeRestoredRun(
        hostReference: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        guard var session = sessions[hostReference],
              session.active,
              session.awaitingResumption,
              let providerReference = session.stored.providerInternalSessionReference,
              let adapter = adapters[session.stored.adapterID]
        else { throw RuntimeHostError.invalidEvent }
        session.awaitingResumption = false
        sessions[hostReference] = session
        let receipt = RuntimeLaunchReceipt(
            runReference: session.stored.runReference,
            providerInternalSessionReference: providerReference,
        )
        do {
            let result = try await consume(receipt, from: adapter, host: hostReference)
            if sessions[hostReference]?.stored.projection.isTerminal == true {
                return resultRespectingStoredTerminal(result, host: hostReference)
            }
            await waitForOperationsBeforeTerminal(hostReference)
            defer { terminalPending.remove(hostReference) }
            try await commit(host: hostReference) { plane in
                plane.finish(result, host: hostReference)
            }
            return resultRespectingStoredTerminal(result, host: hostReference)
        } catch let error as RuntimeHostError {
            try await interruptResumedRunOrRestoreClaim(hostReference)
            throw error
        } catch {
            let normalized = normalizeAdapterError(error)
            try await interruptResumedRunOrRestoreClaim(hostReference)
            throw normalized
        }
    }

    private func interruptResumedRunOrRestoreClaim(
        _ hostReference: ExternalAgentSessionReference,
    ) async throws {
        do {
            try await markInterrupted(hostReference)
        } catch let error as RuntimeHostError {
            restoreResumptionClaimIfNeeded(hostReference)
            throw error
        } catch {
            restoreResumptionClaimIfNeeded(hostReference)
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func restoreResumptionClaimIfNeeded(
        _ hostReference: ExternalAgentSessionReference,
    ) {
        guard var session = sessions[hostReference],
              session.active,
              !session.stored.projection.isTerminal
        else { return }
        session.awaitingResumption = true
        sessions[hostReference] = session
    }
}

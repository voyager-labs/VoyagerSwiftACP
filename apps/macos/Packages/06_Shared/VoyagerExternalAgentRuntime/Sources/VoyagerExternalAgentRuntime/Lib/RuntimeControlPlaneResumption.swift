import Foundation

public extension RuntimeControlPlane {
    func resumeRestoredRun(
        hostReference: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        let claim = try await claimRestoredRun(hostReference)
        guard let adapter = adapters[claim.adapterID] else { throw RuntimeHostError.invalidEvent }
        do {
            let result = try await consume(claim.receipt, from: adapter, host: hostReference)
            if sessions[hostReference]?.stored.projection.isTerminal == true {
                return resultRespectingStoredTerminal(result, host: hostReference)
            }
            beginTerminalTransition(hostReference)
            defer { endTerminalTransition(hostReference) }
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

    private func claimRestoredRun(
        _ hostReference: ExternalAgentSessionReference,
    ) async throws -> RestoredRunClaim {
        try await mutateAfterPersistedTransitions { plane in
            guard var session = plane.sessions[hostReference],
                  session.active,
                  session.awaitingResumption,
                  let providerReference = session.stored.providerInternalSessionReference,
                  plane.adapters[session.stored.adapterID] != nil
            else { throw RuntimeHostError.invalidEvent }
            session.awaitingResumption = false
            plane.sessions[hostReference] = session
            return RestoredRunClaim(
                receipt: RuntimeLaunchReceipt(
                    runReference: session.stored.runReference,
                    providerInternalSessionReference: providerReference,
                ),
                adapterID: session.stored.adapterID,
            )
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

private struct RestoredRunClaim {
    let receipt: RuntimeLaunchReceipt
    let adapterID: RuntimeAdapterID
}

import Foundation

struct RestoredRunClaim {
    let receipt: RuntimeLaunchReceipt
    let adapterID: RuntimeAdapterID
    let lease: UInt64
    let isPersisted: Bool
}

enum RestoredConsumptionResult {
    case provider(RuntimeResult)
    case persistedTerminal(RuntimeResult)
}

enum RuntimeRestoredResumeRaceOutcome {
    case result(RuntimeResult)
    case failure(RuntimeRestoredResumeRaceFailure)
    case cancelled
}

enum RuntimeRestoredResumeRaceFailure {
    case cancellation
    case attemptLost
    case host(RuntimeHostError)
    case terminalEventPersistence
    case heartbeatPersistence
    case providerTerminalAdmission
}

extension RuntimeRestoredResumeRaceOutcome: Sendable {}
extension RuntimeRestoredResumeRaceFailure: Sendable {}

extension RuntimeControlPlane {
    func launchValidatedRestore(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredRunClaim {
        guard let validated = validatedRestoreContexts[host],
              validated.runReference == claim.receipt.runReference,
              validated.adapterID == claim.adapterID,
              validated.lease == claim.lease,
              validated.persistedReceipt.runReference == claim.receipt.runReference,
              validated.persistedReceipt.providerInternalSessionReference == claim.receipt
              .providerInternalSessionReference,
              adapters[claim.adapterID]?.descriptor == validated.adapter.descriptor
        else {
            clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease)
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.persistenceConflict
        }
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: validated.runReference,
            adapterID: validated.adapterID,
            contextPolicy: validated.contextPolicy,
            input: RuntimeSensitiveInput(""),
        )
        do {
            let receipt = try await validated.adapter.launch(request)
            guard receipt.runReference == validated.persistedReceipt.runReference,
                  receipt.providerInternalSessionReference == validated.persistedReceipt
                  .providerInternalSessionReference
            else {
                clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease)
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                throw RuntimeHostError.restartIncompatible
            }
            return RestoredRunClaim(
                receipt: receipt,
                adapterID: claim.adapterID,
                lease: claim.lease,
                isPersisted: claim.isPersisted,
            )
        } catch {
            if let hostError = error as? RuntimeHostError,
               hostError == .restartIncompatible
               || hostError == .staleRestartBinding
               || hostError == .malformedAdapterResponse
            {
                clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease)
            }
            if validatedRestoreContexts[host]?.lease == claim.lease {
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            }
            throw error is RuntimeHostError ? error : normalizeAdapterError(error)
        }
    }
}

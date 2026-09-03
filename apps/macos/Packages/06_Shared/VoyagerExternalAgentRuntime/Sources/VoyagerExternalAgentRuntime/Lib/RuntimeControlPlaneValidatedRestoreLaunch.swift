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

enum RuntimeRestoredLaunchRaceOutcome {
    case launched(RestoredRunClaim)
    case terminal(RuntimeResult)
    case failure(RuntimeRestoredResumeRaceFailure)
    case cancelled
}

extension RuntimeRestoredResumeRaceOutcome: Sendable {}
extension RuntimeRestoredResumeRaceFailure: Sendable {}
extension RuntimeRestoredLaunchRaceOutcome: Sendable {}

extension RuntimeControlPlane {
    private func startValidatedRestore(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeLaunchOperation {
        guard let validated = validatedRestoreContexts[host],
              validated.runReference == claim.receipt.runReference,
              validated.adapterID == claim.adapterID,
              validated.lease == claim.lease,
              validated.persistedReceipt.runReference == claim.receipt.runReference,
              validated.persistedReceipt.providerInternalSessionReference == claim.receipt
              .providerInternalSessionReference,
              adapters[claim.adapterID]?.descriptor == validated.adapter.descriptor,
              activeRestoredResumeAttempts[host] == restoredContext.attemptID,
              sessions[host]?.lease == .resuming(claim.lease)
        else {
            throw RuntimeHostError.persistenceConflict
        }
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: validated.runReference,
            adapterID: validated.adapterID,
            contextPolicy: validated.contextPolicy,
            input: RuntimeSensitiveInput(""),
        )
        return await validated.adapter.startLaunch(request)
    }

    private func launchValidatedRestore(
        operation: RuntimeLaunchOperation,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredRunClaim {
        do {
            let receipt = try await operation.receipt()
            guard validatedRestoreContexts[host]?.lease == claim.lease,
                  activeRestoredResumeAttempts[host] == restoredContext.attemptID,
                  sessions[host]?.lease == .resuming(claim.lease),
                  receipt.runReference == claim.receipt.runReference,
                  receipt.providerInternalSessionReference == claim.receipt.providerInternalSessionReference
            else {
                await operation.cancel()
                guard activeRestoredResumeAttempts[host] == restoredContext.attemptID else {
                    throw RuntimeHostError.persistenceConflict
                }
                clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease)
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease, restoredContext: restoredContext)
                throw RuntimeHostError.restartIncompatible
            }
            return RestoredRunClaim(
                receipt: receipt,
                adapterID: claim.adapterID,
                lease: claim.lease,
                isPersisted: claim.isPersisted,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let hostError = error as? RuntimeHostError,
               hostError == .restartIncompatible || hostError == .staleRestartBinding
               || hostError == .malformedAdapterResponse
            { clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease) }
            if validatedRestoreContexts[host]?.lease == claim.lease,
               activeRestoredResumeAttempts[host] == restoredContext.attemptID
            { try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease, restoredContext: restoredContext) }
            throw error is RuntimeHostError ? error : normalizeAdapterError(error)
        }
    }

    private func restorationHeartbeatDuringLaunch(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult {
        while true {
            try await restorationClock.sleep(restorationHeartbeatInterval)
            try requireRestoredResumeContext(restoredContext, host: host, runReference: claim.receipt.runReference)
            if let terminal = storedTerminalResult(host: host, runReference: claim.receipt.runReference) {
                clearValidatedRestoreContext(host: host, runReference: claim.receipt.runReference, lease: claim.lease)
                finalizeVisibleResumptionTerminal(
                    host: host,
                    runReference: claim.receipt.runReference,
                    lease: claim.lease,
                    restoredContext: restoredContext,
                )
                return terminal
            }
            do {
                try await renewRestorationClaim(
                    host,
                    runReference: claim.receipt.runReference,
                    lease: claim.lease,
                    restoredContext: restoredContext,
                )
            } catch {
                if let terminal = try await resolveHeartbeatFailure(
                    error,
                    host: host,
                    runReference: claim.receipt.runReference,
                    lease: claim.lease,
                    restoredContext: restoredContext,
                ) { return terminal }
                throw error
            }
        }
    }

    func launchRestoredClaimWithHeartbeat(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async -> RuntimeRestoredLaunchRaceOutcome {
        let (stream, continuation) = AsyncStream<RuntimeRestoredLaunchRaceOutcome>.makeStream(
            bufferingPolicy: .bufferingOldest(1),
        )
        let operationTask = Task { [self] in
            try await startValidatedRestore(claim, host: host, restoredContext: restoredContext)
        }
        let launchTask = Task { [self] in
            do {
                let operation = try await operationTask.value
                let result = try await launchValidatedRestore(
                    operation: operation,
                    claim: claim,
                    host: host,
                    restoredContext: restoredContext,
                )
                continuation.yield(.launched(result))
            } catch { continuation.yield(.failure(mapRestoredResumeRaceFailure(error))) }
        }
        let heartbeatTask = Task { [self] in
            do {
                let result = try await restorationHeartbeatDuringLaunch(
                    claim,
                    host: host,
                    restoredContext: restoredContext,
                )
                continuation.yield(.terminal(result))
            } catch { continuation.yield(.failure(mapRestoredResumeRaceFailure(error))) }
        }
        func cancelOperationAndRestore() async {
            if let operation = try? await operationTask.value { await operation.cancel() }
            try? await restoreResumptionClaimIfNeeded(
                host,
                lease: claim.lease,
                restoredContext: restoredContext,
            )
        }
        defer {
            launchTask.cancel()
            operationTask.cancel()
            heartbeatTask.cancel()
            continuation.finish()
        }
        return await withTaskCancellationHandler(operation: {
            var iterator = stream.makeAsyncIterator()
            guard let outcome = await iterator.next() else {
                await cancelOperationAndRestore()
                return .cancelled
            }
            do {
                try Task.checkCancellation()
            } catch {
                await cancelOperationAndRestore()
                return .cancelled
            }
            if case .cancelled = outcome {
                await cancelOperationAndRestore()
                return .cancelled
            }
            if case .launched = outcome {} else { await cancelOperationAndRestore() }
            return outcome
        }, onCancel: { continuation.yield(.cancelled) })
    }
}

extension RuntimeControlPlane {
    func mapRestoredResumeRaceFailure(_ error: any Error) -> RuntimeRestoredResumeRaceFailure {
        if error is CancellationError { return .cancellation }
        if error is RuntimeRestoredResumeAttemptError { return .attemptLost }
        if error is RuntimeTerminalEventPersistenceError { return .terminalEventPersistence }
        if error is RuntimeRestorationHeartbeatPersistenceError { return .heartbeatPersistence }
        if error is RuntimeProviderTerminalAdmissionError { return .providerTerminalAdmission }
        if let error = error as? RuntimeHostError { return .host(error) }
        if let error = error as? RuntimeAdapterFailure {
            return .host(.adapterFailure(error.kind, error.diagnosticCode))
        }
        return .host(.adapterUnavailable)
    }
}

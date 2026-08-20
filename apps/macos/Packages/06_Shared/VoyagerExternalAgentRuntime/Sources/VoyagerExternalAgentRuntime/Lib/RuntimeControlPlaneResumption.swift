import Foundation

private enum RuntimeRestorationHeartbeatPersistenceError: Error {
    case persistenceFailure
}

public extension RuntimeControlPlane {
    func resumeRestoredRun(
        hostReference: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        let claim = try await claimRestoredRun(hostReference)
        guard let adapter = adapters[claim.adapterID] else { throw RuntimeHostError.invalidEvent }
        let consumption = try await consumeRestoredClaim(claim, from: adapter, host: hostReference)
        if case let .persistedTerminal(terminal) = consumption { return terminal }
        guard case let .provider(result) = consumption else { throw RuntimeHostError.invalidEvent }
        if let terminal = try await reconcileConsumedResult(
            result,
            host: hostReference,
            lease: claim.lease,
        ) {
            return terminal
        }
        do {
            return try await persistTerminalResult(result, host: hostReference, lease: claim.lease)
        } catch {
            try? await recoverTerminalPersistenceClaim(host: hostReference, lease: claim.lease)
            throw error
        }
    }

    private func consumeRestoredClaim(
        _ claim: RestoredRunClaim,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        do {
            if claim.isPersisted {
                return try await .provider(consumeWithRestorationHeartbeat(
                    claim.receipt,
                    from: adapter,
                    host: host,
                    lease: claim.lease,
                ))
            }
            return try await .provider(consume(claim.receipt, from: adapter, host: host))
        } catch RuntimeTerminalEventPersistenceError.persistenceFailure {
            try await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.persistenceFailure
        } catch RuntimeRestorationHeartbeatPersistenceError.persistenceFailure {
            try await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.persistenceFailure
        } catch is CancellationError {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw CancellationError()
        } catch let error as RuntimeHostError {
            return try await resolveResumedHostError(error, claim: claim, host: host)
        } catch {
            return try await resolveResumedAdapterError(error, claim: claim, host: host)
        }
    }

    private func resolveResumedHostError(
        _ error: RuntimeHostError,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        switch error {
        case .persistenceConflict, .persistenceFailure, .invalidPersistedState, .unsupportedSchemaVersion:
            break
        default:
            if let terminal = try await resumedPersistedTerminal(
                host,
                runReference: claim.receipt.runReference,
                lease: claim.lease,
            ) {
                return .persistedTerminal(terminal)
            }
        }
        try await propagateResumedRunFailure(error, host: host, lease: claim.lease)
    }

    private func resolveResumedAdapterError(
        _ error: any Error,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        if let terminal = try await resumedPersistedTerminal(
            host,
            runReference: claim.receipt.runReference,
            lease: claim.lease,
        ) {
            return .persistedTerminal(terminal)
        }
        let normalized = normalizeAdapterError(error)
        try await interruptResumedRunOrRestoreClaim(host, lease: claim.lease)
        throw normalized
    }

    private func resumedPersistedTerminal(
        _ hostReference: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        do {
            guard let terminal = try await persistedTerminalResult(
                host: hostReference,
                runReference: runReference,
            ) else { return nil }
            try await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            return terminal
        } catch {
            try? await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            throw error
        }
    }

    private func claimRestoredRun(
        _ hostReference: ExternalAgentSessionReference,
    ) async throws -> RestoredRunClaim {
        try await commit(host: hostReference) { plane, registry in
            guard var session = registry[hostReference],
                  case let .restored(lease) = session.lease,
                  session.stored.restorationClaim?.ownerToken == plane.restorationOwnerToken,
                  let providerReference = session.stored.providerInternalSessionReference,
                  plane.adapters[session.stored.adapterID] != nil
            else { throw RuntimeHostError.invalidEvent }
            session.stored = session.stored.withRestorationClaim(plane.makeRestorationClaim())
            session.lease = .resuming(lease)
            registry[hostReference] = session
            return RestoredRunClaim(
                receipt: RuntimeLaunchReceipt(
                    runReference: session.stored.runReference,
                    providerInternalSessionReference: providerReference,
                ),
                adapterID: session.stored.adapterID,
                lease: lease,
                isPersisted: true,
            )
        }
    }

    private func consumeWithRestorationHeartbeat(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        try await withThrowingTaskGroup(of: RuntimeResult.self) { group in
            group.addTask { try await self.consume(receipt, from: adapter, host: host) }
            group.addTask {
                try await self.restorationHeartbeatResult(
                    host: host,
                    receipt: receipt,
                    lease: lease,
                )
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw RuntimeHostError.invalidEvent }
            try Task.checkCancellation()
            return result
        }
    }

    private func restorationHeartbeatResult(
        host: ExternalAgentSessionReference,
        receipt: RuntimeLaunchReceipt,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        while true {
            try await Task.sleep(for: restorationHeartbeatInterval)
            do {
                try await renewRestorationClaim(host, lease: lease)
            } catch {
                if let terminal = try await resolveHeartbeatFailure(
                    error,
                    host: host,
                    runReference: receipt.runReference,
                ) {
                    return terminal
                }
                throw error
            }
        }
    }

    private func resolveHeartbeatFailure(
        _ error: any Error,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult? {
        if error is CancellationError { throw CancellationError() }
        do {
            if let terminal = try await persistedTerminalResult(host: host, runReference: runReference) {
                return terminal
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeRestorationHeartbeatPersistenceError.persistenceFailure
        }
        guard let hostError = error as? RuntimeHostError else { return nil }
        switch hostError {
        case .persistenceConflict:
            throw hostError
        case .persistenceFailure:
            throw RuntimeRestorationHeartbeatPersistenceError.persistenceFailure
        default:
            return nil
        }
    }

    private func propagateResumedRunFailure(
        _ error: RuntimeHostError,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> Never {
        switch error {
        case .persistenceConflict, .persistenceFailure, .invalidPersistedState, .unsupportedSchemaVersion:
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
            throw error
        default:
            try await interruptResumedRunOrRestoreClaim(host, lease: lease)
            throw error
        }
    }

    private func renewRestorationClaim(
        _ host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws {
        _ = try await commit(host: host) { plane, registry in
            guard var session = registry[host],
                  session.lease == .resuming(lease),
                  session.stored.restorationClaim?.ownerToken == plane.restorationOwnerToken
            else { throw RuntimeHostError.invalidEvent }
            session.stored = session.stored.withRestorationClaim(plane.makeRestorationClaim())
            registry[host] = session
        }
    }

    private func interruptResumedRunOrRestoreClaim(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws {
        do {
            _ = try await commit(host: hostReference) { plane, registry in
                try plane.interruptTransition(
                    host: hostReference,
                    lease: lease,
                    in: &registry,
                )
            }
        } catch is CancellationError {
            try await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            throw CancellationError()
        } catch {
            try await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            if let hostError = error as? RuntimeHostError { throw hostError }
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func restoreResumptionClaimIfNeeded(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws {
        try await mutateAfterPersistedTransitions { plane in
            guard var session = plane.sessions[hostReference],
                  session.lease == .resuming(lease)
            else { return }
            session.lease = session.stored.projection.isTerminal ? .none : .restored(lease)
            plane.sessions[hostReference] = session
        }
    }
}

private struct RestoredRunClaim {
    let receipt: RuntimeLaunchReceipt
    let adapterID: RuntimeAdapterID
    let lease: UInt64
    let isPersisted: Bool
}

private enum RestoredConsumptionResult {
    case provider(RuntimeResult)
    case persistedTerminal(RuntimeResult)
}

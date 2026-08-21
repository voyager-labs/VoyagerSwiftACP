import Foundation

private enum RuntimeRestorationHeartbeatPersistenceError: Error {
    case persistenceFailure
}

public extension RuntimeControlPlane {
    func resumeRestoredRun(
        hostReference: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        if let runReference = sessions[hostReference]?.stored.runReference,
           let terminal = storedTerminalResult(host: hostReference, runReference: runReference)
        {
            if case let .restored(lease) = sessions[hostReference]?.lease {
                finalizeVisibleResumptionTerminal(
                    host: hostReference,
                    runReference: runReference,
                    lease: lease,
                )
            }
            return terminal
        }
        let claim = try await claimRestoredRun(hostReference)
        guard let adapter = adapters[claim.adapterID] else { throw RuntimeHostError.invalidEvent }
        let consumption = try await consumeRestoredClaim(claim, from: adapter, host: hostReference)
        if case let .persistedTerminal(terminal) = consumption {
            finalizeVisibleResumptionTerminal(
                host: hostReference,
                runReference: terminal.runReference,
                lease: claim.lease,
            )
            return terminal
        }
        guard case let .provider(result) = consumption else { throw RuntimeHostError.invalidEvent }
        if let terminal = storedTerminalResult(
            host: hostReference,
            runReference: result.runReference,
        ) {
            finalizeVisibleResumptionTerminal(
                host: hostReference,
                runReference: result.runReference,
                lease: claim.lease,
            )
            return terminal.outcome == result.outcome ? result : terminal
        }
        try await validateRestorationResultAdmission(
            claim,
            host: hostReference,
            runReference: result.runReference,
        )
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
            try? await restoreResumptionClaimIfNeeded(hostReference, lease: claim.lease)
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
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.persistenceFailure
        } catch RuntimeProviderTerminalAdmissionError.rejected {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.invalidEvent
        } catch is CancellationError {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw CancellationError()
        } catch let error as RuntimeHostError {
            return try await resolveResumedHostError(error, claim: claim, host: host)
        } catch {
            return try await resolveResumedAdapterError(error, claim: claim, host: host)
        }
    }

    private func validateRestorationResultAdmission(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) async throws {
        guard claim.isPersisted else { return }
        switch restorationHeartbeatDecision(
            host: host,
            runReference: runReference,
            lease: claim.lease,
            now: restorationClock.now(),
        ) {
        case .renewClaim:
            return
        case .restoreClaim:
            try await recoverRestorationClaimAfterExpiry(
                host: host,
                runReference: runReference,
                lease: claim.lease,
                now: restorationClock.now(),
            )
            throw RuntimeHostError.persistenceConflict
        case .stale:
            try await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw RuntimeHostError.persistenceConflict
        case let .throwHost(error):
            throw error
        case .acquireClaim, .beginResume, .adoptPersisted:
            throw RuntimeHostError.invalidEvent
        }
    }

    private func resolveResumedHostError(
        _ error: RuntimeHostError,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        try await resolveResumedFailure(error, claim: claim, host: host)
    }

    private func resolveResumedAdapterError(
        _ error: any Error,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        try await resolveResumedFailure(
            normalizeAdapterError(error),
            claim: claim,
            host: host,
        )
    }

    private func resolveResumedFailure(
        _ error: RuntimeHostError,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        switch error {
        case .persistenceConflict, .persistenceFailure, .invalidPersistedState, .unsupportedSchemaVersion:
            return try await propagateResumedRunFailure(error, claim: claim, host: host)
        case .adapterFailure(.processExit, _), .adapterFailure(.transportLoss, _):
            if let terminal = try await terminalBeforeResumedInterruption(
                claim: claim,
                host: host,
            ) {
                return .persistedTerminal(terminal)
            }
            return try await propagateResumedRunFailure(error, claim: claim, host: host)
        default:
            do {
                if let terminal = try await persistedTerminalResult(
                    host: host,
                    runReference: claim.receipt.runReference,
                ) {
                    try await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                    return .persistedTerminal(terminal)
                }
            } catch is CancellationError {
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                throw CancellationError()
            } catch let probeError as RuntimeHostError {
                switch probeError {
                case .invalidPersistedState, .unsupportedSchemaVersion:
                    try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                    throw probeError
                case .persistenceConflict, .persistenceFailure:
                    break
                default:
                    throw probeError
                }
            }
            return try await interruptResumedRunOrRestoreClaim(
                error,
                receipt: claim.receipt,
                host: host,
                lease: claim.lease,
            )
        }
    }

    private func terminalBeforeResumedInterruption(
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult? {
        if let terminal = storedTerminalResult(
            host: host,
            runReference: claim.receipt.runReference,
        ) {
            finalizeVisibleResumptionTerminal(
                host: host,
                runReference: claim.receipt.runReference,
                lease: claim.lease,
            )
            return terminal
        }
        do {
            guard let terminal = try await persistedTerminalResult(
                host: host,
                runReference: claim.receipt.runReference,
            ) else { return nil }
            finalizeVisibleResumptionTerminal(
                host: host,
                runReference: claim.receipt.runReference,
                lease: claim.lease,
            )
            return terminal
        } catch is CancellationError {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw CancellationError()
        } catch let error as RuntimeHostError {
            switch error {
            case .persistenceConflict, .persistenceFailure:
                return nil
            case .invalidPersistedState, .unsupportedSchemaVersion:
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                throw error
            default:
                throw error
            }
        }
    }

    private func finalizeVisibleResumptionTerminal(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) {
        guard var session = sessions[host],
              session.stored.runReference == runReference,
              session.stored.projection.isTerminal,
              session.lease == .resuming(lease) || session.lease == .restored(lease)
        else { return }
        session.lease = .none
        session.revision += 1
        sessions[host] = session
    }

    private func claimRestoredRun(
        _ hostReference: ExternalAgentSessionReference,
    ) async throws -> RestoredRunClaim {
        try await commit(host: hostReference) { plane, registry in
            guard var session = registry[hostReference],
                  case let .restored(lease) = session.lease,
                  let providerReference = session.stored.providerInternalSessionReference,
                  plane.adapters[session.stored.adapterID] != nil
            else { throw RuntimeHostError.invalidEvent }
            let decision = RuntimeRestoreResumeDecisionTable.decide(
                .beginResume,
                on: RuntimeRestoreResumeDecisionTable.Snapshot(
                    projection: session.stored.projection,
                    lease: session.lease,
                    claimState: plane.restorationClaimState(
                        session.stored.restorationClaim,
                        now: plane.restorationClock.now(),
                    ),
                ),
            )
            switch decision {
            case .beginResume:
                break
            case .stale, .restoreClaim:
                throw RuntimeHostError.persistenceConflict
            case let .throwHost(error):
                throw error
            case .acquireClaim, .renewClaim, .adoptPersisted:
                throw RuntimeHostError.invalidEvent
            }
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
            try await restorationClock.sleep(restorationHeartbeatInterval)
            do {
                try await renewRestorationClaim(
                    host,
                    runReference: receipt.runReference,
                    lease: lease,
                )
            } catch let error as RuntimeHostError {
                switch error {
                case .invalidPersistedState, .unsupportedSchemaVersion:
                    throw error
                default:
                    if let terminal = try await resolveHeartbeatFailure(
                        error,
                        host: host,
                        runReference: receipt.runReference,
                    ) {
                        return terminal
                    }
                    throw error
                }
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
            if let terminal = storedTerminalResult(host: host, runReference: runReference) {
                return terminal
            }
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
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
    ) async throws -> RestoredConsumptionResult {
        let runReference = claim.receipt.runReference
        let lease = claim.lease
        switch error {
        case .persistenceConflict, .persistenceFailure, .invalidPersistedState, .unsupportedSchemaVersion:
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
            throw error
        case .adapterFailure(.processExit, _), .adapterFailure(.transportLoss, _):
            do {
                let hasPersistedProof = try await fencePersistedOwner(
                    host,
                    lease: lease,
                    runReference: runReference,
                )
                if let terminal = storedTerminalResult(host: host, runReference: runReference) {
                    return .persistedTerminal(terminal)
                }
                if hasPersistedProof,
                   let session = sessions[host],
                   session.stored.runReference == runReference,
                   session.lease == .resuming(lease),
                   restorationClaimState(session.stored.restorationClaim, now: restorationClock.now()) == .expired
                {
                    try await recoverRestorationClaimAfterExpiry(
                        host: host,
                        runReference: runReference,
                        lease: lease,
                        now: restorationClock.now(),
                    )
                }
                if !hasPersistedProof {
                    deactivateLocalResumptionLeaseIfOwned(
                        host: host,
                        runReference: runReference,
                        lease: lease,
                    )
                }
            } catch let fencingError as RuntimeHostError {
                applyCleanupFailedDecision(host: host, runReference: runReference)
                deactivateLocalResumptionLeaseIfOwned(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                )
                switch fencingError {
                case .invalidPersistedState, .unsupportedSchemaVersion:
                    throw fencingError
                default:
                    break
                }
            } catch {
                applyCleanupFailedDecision(host: host, runReference: runReference)
                deactivateLocalResumptionLeaseIfOwned(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                )
            }
            throw error
        default:
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
            throw error
        }
    }

    private func renewRestorationClaim(
        _ host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws {
        let now = restorationClock.now()
        switch restorationHeartbeatDecision(
            host: host,
            runReference: runReference,
            lease: lease,
            now: now,
        ) {
        case .renewClaim:
            do {
                try await applyRestorationClaimRenewal(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                    expiresAt: now.addingTimeInterval(60),
                )
            } catch RuntimeHostError.persistenceConflict {
                try await repairRestorationClaimAfterConflict(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                )
            }
        case .restoreClaim:
            try await recoverRestorationClaimAfterExpiry(
                host: host,
                runReference: runReference,
                lease: lease,
                now: now,
            )
            throw RuntimeHostError.persistenceConflict
        case .stale:
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
            throw RuntimeHostError.persistenceConflict
        case let .throwHost(error):
            throw error
        case .acquireClaim, .beginResume, .adoptPersisted:
            throw RuntimeHostError.invalidEvent
        }
    }

    private func recoverRestorationClaimAfterExpiry(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
        now: Date,
    ) async throws {
        guard let claimState = sessions[host].map({
            restorationClaimState($0.stored.restorationClaim, now: now)
        }) else { throw RuntimeHostError.invalidEvent }
        switch claimState {
        case .expired:
            do {
                try await clearExpiredRestorationClaim(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                    now: now,
                )
            } catch RuntimeHostError.persistenceConflict {
                try? await restoreResumptionClaimIfNeeded(
                    host,
                    lease: lease,
                    fencePersistedOwner: true,
                )
            }
        case .absent:
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
        case .ownedLive, .foreignLive:
            throw RuntimeHostError.invalidEvent
        }
    }

    private func applyRestorationClaimRenewal(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
        expiresAt: Date,
    ) async throws {
        _ = try await commit(host: host) { plane, registry in
            guard var session = registry[host],
                  session.stored.runReference == runReference,
                  session.lease == .resuming(lease),
                  session.stored.restorationClaim?.ownerToken == plane.restorationOwnerToken,
                  session.stored.restorationClaim?.expiresAt ?? .distantPast > expiresAt.addingTimeInterval(-60)
            else { throw RuntimeHostError.invalidEvent }
            session.stored = session.stored.withRestorationClaim(RuntimeRestorationClaim(
                ownerToken: plane.restorationOwnerToken,
                expiresAt: expiresAt,
            ))
            registry[host] = session
        }
    }

    private func repairRestorationClaimAfterConflict(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws {
        let decision = try await reconcileRestorationClaimAfterConflict(
            host: host,
            runReference: runReference,
            lease: lease,
        )
        guard decision == .renewClaim else {
            try await restoreResumptionClaimIfNeeded(host, lease: lease)
            throw RuntimeHostError.persistenceConflict
        }

        do {
            let now = restorationClock.now()
            try await applyRestorationClaimRenewal(
                host: host,
                runReference: runReference,
                lease: lease,
                expiresAt: now.addingTimeInterval(60),
            )
        } catch RuntimeHostError.persistenceConflict {
            _ = try await reconcileRestorationClaimAfterConflict(
                host: host,
                runReference: runReference,
                lease: lease,
            )
            throw RuntimeHostError.persistenceConflict
        }
    }

    private func reconcileRestorationClaimAfterConflict(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws -> RuntimeRestoreResumeDecisionTable.Decision {
        try await withPersistedState { plane, loaded in
            guard let loaded else { throw RuntimeHostError.persistenceConflict }
            let expectedStored = plane.sessions[host]?.stored
            plane.sessions = plane.reconciledRegistry(
                candidate: plane.sessions,
                persisted: loaded,
            )
            guard var session = plane.sessions[host],
                  session.stored.runReference == runReference
            else { return .stale }

            if session.stored.restorationClaim?.ownerToken == plane.restorationOwnerToken {
                session.lease = .resuming(lease)
                plane.sessions[host] = session
            }
            let decision = plane.restorationHeartbeatDecision(
                host: host,
                runReference: runReference,
                lease: lease,
                now: plane.restorationClock.now(),
            )
            guard expectedStored != session.stored else {
                return RuntimeRestoreResumeDecisionTable.decide(
                    .persistConflict,
                    on: RuntimeRestoreResumeDecisionTable.Snapshot(
                        projection: session.stored.projection,
                        lease: session.lease,
                        claimState: session.stored.restorationClaim?.ownerToken
                            == plane.restorationOwnerToken
                            ? .ownedLive
                            : .foreignLive,
                    ),
                )
            }
            return decision
        }
    }

    private func restorationHeartbeatDecision(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
        now: Date,
    ) -> RuntimeRestoreResumeDecisionTable.Decision {
        guard let session = sessions[host], session.stored.runReference == runReference else {
            return .stale
        }
        return RuntimeRestoreResumeDecisionTable.decide(
            .heartbeat,
            on: RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: session.stored.projection,
                lease: session.lease == .resuming(lease) ? .resuming(lease) : session.lease,
                claimState: restorationClaimState(session.stored.restorationClaim, now: now),
            ),
        )
    }

    private func interruptResumedRunOrRestoreClaim(
        _ error: RuntimeHostError,
        receipt: RuntimeLaunchReceipt,
        host hostReference: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RestoredConsumptionResult {
        do {
            if let terminal = try await interruptAfterConsumptionFailure(
                receipt: receipt,
                host: hostReference,
                lease: lease,
            ) {
                return .persistedTerminal(terminal)
            }
        } catch is CancellationError {
            try? await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            throw CancellationError()
        } catch {
            applyCleanupFailedDecision(
                host: hostReference,
                runReference: receipt.runReference,
            )
            try? await restoreResumptionClaimIfNeeded(hostReference, lease: lease)
            if storedTerminalResult(host: hostReference, runReference: receipt.runReference) == nil {
                if let hostError = error as? RuntimeHostError { throw hostError }
                throw RuntimeHostError.persistenceFailure
            }
        }
        throw error
    }

    private func restoreResumptionClaimIfNeeded(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
        fencePersistedOwner shouldFencePersistedOwner: Bool = false,
    ) async throws {
        if shouldFencePersistedOwner {
            _ = try await fencePersistedOwner(hostReference, lease: lease)
            return
        }
        let now = restorationClock.now()
        if let session = sessions[hostReference],
           case .resuming(lease) = session.lease,
           restorationClaimState(session.stored.restorationClaim, now: now) == .expired
        {
            let runReference = session.stored.runReference
            let recovery = Task.detached { [self] in
                try await recoverRestorationClaimAfterExpiry(
                    host: hostReference,
                    runReference: runReference,
                    lease: lease,
                    now: now,
                )
            }
            try await recovery.value
            return
        }
        try await mutateAfterPersistedTransitions { plane in
            plane.restoreLocalResumptionClaimIfNeeded(hostReference, lease: lease)
        }
    }

    private func fencePersistedOwner(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
        runReference: RuntimeRunReference? = nil,
    ) async throws -> Bool {
        try await withPersistedState { plane, loaded in
            guard let loaded else { return false }
            let expectedSession = plane.sessions[hostReference]
            plane.sessions = plane.reconciledRegistry(
                candidate: plane.sessions,
                persisted: loaded,
            )
            if let runReference,
               let adopted = plane.adoptingPersistedTerminal(
                   host: hostReference,
                   runReference: runReference,
                   expectedSession: expectedSession,
                   loaded: loaded,
               )
            {
                plane.sessions[hostReference] = adopted
                plane.finalizeVisibleResumptionTerminal(
                    host: hostReference,
                    runReference: runReference,
                    lease: lease,
                )
                return true
            }
            plane.restoreLocalResumptionClaimIfNeeded(hostReference, lease: lease)
            return true
        }
    }

    private func deactivateLocalResumptionLeaseIfOwned(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) {
        guard var session = sessions[host],
              session.stored.runReference == runReference,
              session.lease == .resuming(lease)
        else { return }
        session.lease = .none
        session.revision += 1
        sessions[host] = session
    }

    private func clearExpiredRestorationClaim(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
        now: Date,
    ) async throws {
        try await commit(host: host) { plane, registry in
            guard var session = registry[host],
                  session.stored.runReference == runReference,
                  session.lease == .resuming(lease),
                  session.stored.restorationClaim?.ownerToken == plane.restorationOwnerToken,
                  plane.restorationClaimState(session.stored.restorationClaim, now: now) == .expired
            else { throw RuntimeHostError.persistenceConflict }
            session.stored = session.stored.withRestorationClaim(nil)
            session.lease = .none
            session.revision += 1
            registry[host] = session
        }
    }

    private func restoreLocalResumptionClaimIfNeeded(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
    ) {
        guard var session = sessions[hostReference],
              session.lease == .resuming(lease)
        else { return }
        let decision = RuntimeRestoreResumeDecisionTable.decide(
            .restoreAfterFailure,
            on: RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: session.stored.projection,
                lease: session.lease,
                claimState: restorationClaimState(
                    session.stored.restorationClaim,
                    now: restorationClock.now(),
                ),
            ),
        )
        if decision == .stale, session.stored.projection.isTerminal {
            session.lease = .none
            sessions[hostReference] = session
            return
        }
        guard restorationClaimState(session.stored.restorationClaim, now: restorationClock.now()) != .expired
        else { return }
        guard decision == .restoreClaim else { return }
        session.lease = .restored(lease)
        sessions[hostReference] = session
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

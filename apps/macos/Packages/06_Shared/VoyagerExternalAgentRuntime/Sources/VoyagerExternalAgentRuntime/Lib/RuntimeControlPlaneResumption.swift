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
        let claim: RestoredRunClaim
        do {
            claim = try await claimRestoredRun(hostReference)
        } catch RuntimeHostError.persistenceConflict {
            guard let session = sessions[hostReference],
                  case let .restored(lease) = session.lease
            else { throw RuntimeHostError.persistenceConflict }
            if let terminal = try await reconcileResumeClaimConflict(
                host: hostReference,
                runReference: session.stored.runReference,
                lease: lease,
            ) {
                return terminal
            }
            throw RuntimeHostError.persistenceConflict
        }
        let attemptID = try beginRestoredResumeAttempt(
            host: hostReference,
            runReference: claim.receipt.runReference,
            lease: claim.lease,
        )
        let restoredContext = RuntimeRestoredResumeContext(
            attemptID: attemptID,
            lease: claim.lease,
        )
        defer {
            invalidateRestoredResumeAttempt(attemptID, host: hostReference)
        }
        if let terminal = try await terminalAfterRestorationClaim(
            claim,
            host: hostReference,
            restoredContext: restoredContext,
        ) {
            return terminal
        }
        guard let adapter = adapters[claim.adapterID] else { throw RuntimeHostError.invalidEvent }
        return try await finishRestoredResumeAttempt(
            claim,
            from: adapter,
            host: hostReference,
            restoredContext: restoredContext,
        )
    }

    private func finishRestoredResumeAttempt(
        _ claim: RestoredRunClaim,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult {
        let consumption = try await consumeRestoredClaim(
            claim,
            from: adapter,
            host: host,
            restoredContext: restoredContext,
        )
        if case let .persistedTerminal(terminal) = consumption {
            finalizeVisibleResumptionTerminal(
                host: host,
                runReference: terminal.runReference,
                lease: claim.lease,
                restoredContext: restoredContext,
            )
            return terminal
        }
        guard case let .provider(result) = consumption else { throw RuntimeHostError.invalidEvent }
        if let terminal = storedTerminalResult(host: host, runReference: result.runReference) {
            finalizeVisibleResumptionTerminal(
                host: host,
                runReference: result.runReference,
                lease: claim.lease,
                restoredContext: restoredContext,
            )
            return terminal.outcome == result.outcome ? result : terminal
        }
        try await validateRestorationResultAdmission(
            claim,
            host: host,
            runReference: result.runReference,
            restoredContext: restoredContext,
        )
        if let terminal = try await reconcileConsumedResult(
            result,
            host: host,
            lease: claim.lease,
            restoredContext: restoredContext,
        ) {
            return terminal
        }
        do {
            return try await persistTerminalResult(
                result,
                host: host,
                lease: claim.lease,
                restoredContext: restoredContext,
            )
        } catch {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw error
        }
    }

    private func consumeRestoredClaim(
        _ claim: RestoredRunClaim,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredConsumptionResult {
        do {
            if claim.isPersisted {
                return try await .provider(consumeWithRestorationHeartbeat(
                    claim.receipt,
                    from: adapter,
                    host: host,
                    lease: claim.lease,
                    restoredContext: restoredContext,
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
        } catch is RuntimeRestoredResumeAttemptError {
            throw RuntimeHostError.persistenceConflict
        } catch let error as RuntimeHostError {
            guard activeRestoredResumeAttempts[host] == restoredContext.attemptID else {
                throw error
            }
            return try await resolveResumedHostError(
                error,
                claim: claim,
                host: host,
                restoredContext: restoredContext,
            )
        } catch {
            guard activeRestoredResumeAttempts[host] == restoredContext.attemptID else {
                throw error
            }
            return try await resolveResumedAdapterError(
                error,
                claim: claim,
                host: host,
                restoredContext: restoredContext,
            )
        }
    }

    private func terminalAfterRestorationClaim(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult? {
        if pendingPersistenceMutations[host, default: 0] > 0 {
            do {
                _ = try await mutateAfterPersistedTransitions { _ in () }
            } catch is CancellationError {
                // 직렬화 경계에서 즉시 탈출한 취소도 기존 checkCancellation 경로와 동일하게 복구한다.
                try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
                throw CancellationError()
            }
        }
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            try? await restoreResumptionClaimIfNeeded(host, lease: claim.lease)
            throw CancellationError()
        }
        try requireRestoredResumeContext(
            restoredContext,
            host: host,
            runReference: claim.receipt.runReference,
        )
        guard let terminal = storedTerminalResult(
            host: host,
            runReference: claim.receipt.runReference,
        ) else { return nil }
        finalizeVisibleResumptionTerminal(
            host: host,
            runReference: claim.receipt.runReference,
            lease: claim.lease,
            restoredContext: restoredContext,
        )
        return terminal
    }

    private func validateRestorationResultAdmission(
        _ claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws {
        guard claim.isPersisted else { return }
        try requireRestoredResumeContext(
            restoredContext,
            host: host,
            runReference: runReference,
        )
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
                restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredConsumptionResult {
        try await resolveResumedFailure(
            error,
            claim: claim,
            host: host,
            restoredContext: restoredContext,
        )
    }

    private func resolveResumedAdapterError(
        _ error: any Error,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredConsumptionResult {
        try await resolveResumedFailure(
            normalizeAdapterError(error),
            claim: claim,
            host: host,
            restoredContext: restoredContext,
        )
    }

    private func resolveResumedFailure(
        _ error: RuntimeHostError,
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredConsumptionResult {
        try requireRestoredResumeContext(
            restoredContext,
            host: host,
            runReference: claim.receipt.runReference,
        )
        switch error {
        case .persistenceConflict, .persistenceFailure, .invalidPersistedState, .unsupportedSchemaVersion:
            return try await propagateResumedRunFailure(
                error,
                claim: claim,
                host: host,
                restoredContext: restoredContext,
            )
        case .adapterFailure(.processExit, _), .adapterFailure(.transportLoss, _):
            if let terminal = try await terminalBeforeResumedInterruption(
                claim: claim,
                host: host,
                restoredContext: restoredContext,
            ) {
                return .persistedTerminal(terminal)
            }
            return try await propagateResumedRunFailure(
                error,
                claim: claim,
                host: host,
                restoredContext: restoredContext,
            )
        default:
            do {
                if let terminal = try await persistedTerminalResult(
                    host: host,
                    runReference: claim.receipt.runReference,
                    restoredContext: restoredContext,
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
                restoredContext: restoredContext,
            )
        }
    }

    private func terminalBeforeResumedInterruption(
        claim: RestoredRunClaim,
        host: ExternalAgentSessionReference,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult? {
        try requireRestoredResumeContext(
            restoredContext,
            host: host,
            runReference: claim.receipt.runReference,
        )
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
                restoredContext: restoredContext,
            ) else { return nil }
            finalizeVisibleResumptionTerminal(
                host: host,
                runReference: claim.receipt.runReference,
                lease: claim.lease,
                restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) {
        if let restoredContext {
            guard activeRestoredResumeAttempts[host] == restoredContext.attemptID else { return }
        }
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

    private func reconcileResumeClaimConflict(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        try await withPersistedState { plane, loaded in
            guard let expected = plane.sessions[host],
                  expected.stored.runReference == runReference,
                  expected.lease == .restored(lease)
            else { return nil }
            if let adopted = plane.adoptingPersistedTerminal(
                host: host,
                runReference: runReference,
                expectedSession: expected,
                loaded: loaded,
            ) {
                plane.sessions[host] = adopted
                plane.finalizeVisibleResumptionTerminal(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                )
                return plane.terminalResult(for: adopted.stored)
            }

            guard let loaded else {
                plane.sessions.removeValue(forKey: host)
                return nil
            }
            plane.sessions = plane.reconciledRegistry(
                candidate: plane.sessions,
                persisted: loaded,
            )
            guard var persisted = plane.sessions[host],
                  persisted.stored.runReference == runReference,
                  !persisted.stored.projection.isTerminal
            else { return nil }
            switch plane.restorationClaimState(
                persisted.stored.restorationClaim,
                now: plane.restorationClock.now(),
            ) {
            case .absent, .expired, .foreignLive:
                persisted.lease = .none
                persisted.revision = max(persisted.revision, expected.revision) + 1
                plane.sessions[host] = persisted
            case .ownedLive:
                persisted.lease = .restored(lease)
                persisted.revision = max(persisted.revision, expected.revision) + 1
                plane.sessions[host] = persisted
            }
            return nil
        }
    }

    private func consumeWithRestorationHeartbeat(
        _ receipt: RuntimeLaunchReceipt,
        from adapter: any ExternalAgentRuntimeAdapter,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult {
        let (stream, continuation) = AsyncStream<RuntimeRestoredResumeRaceOutcome>.makeStream(
            bufferingPolicy: .bufferingOldest(1),
        )
        let providerTask = Task { [self] in
            do {
                try await continuation.yield(.result(consume(
                    receipt,
                    from: adapter,
                    host: host,
                    restoredContext: restoredContext,
                )))
            } catch {
                continuation.yield(.failure(mapRestoredResumeRaceFailure(error)))
            }
        }
        let heartbeatTask = Task { [self] in
            do {
                try await continuation.yield(.result(restorationHeartbeatResult(
                    host: host,
                    receipt: receipt,
                    lease: lease,
                    restoredContext: restoredContext,
                )))
            } catch {
                continuation.yield(.failure(mapRestoredResumeRaceFailure(error)))
            }
        }
        defer {
            providerTask.cancel()
            heartbeatTask.cancel()
            continuation.finish()
        }
        return try await withTaskCancellationHandler(operation: {
            var iterator = stream.makeAsyncIterator()
            guard let outcome = await iterator.next() else { throw RuntimeHostError.invalidEvent }
            try Task.checkCancellation()
            switch outcome {
            case let .result(result):
                return result
            case let .failure(failure):
                try throwRestoredResumeRaceFailure(failure)
            case .cancelled:
                throw CancellationError()
            }
        }, onCancel: {
            continuation.yield(.cancelled)
        })
    }

    private func mapRestoredResumeRaceFailure(_ error: any Error) -> RuntimeRestoredResumeRaceFailure {
        if error is CancellationError {
            return .cancellation
        }
        if error is RuntimeRestoredResumeAttemptError {
            return .attemptLost
        }
        if error is RuntimeTerminalEventPersistenceError {
            return .terminalEventPersistence
        }
        if error is RuntimeRestorationHeartbeatPersistenceError {
            return .heartbeatPersistence
        }
        if error is RuntimeProviderTerminalAdmissionError {
            return .providerTerminalAdmission
        }
        if let error = error as? RuntimeHostError {
            return .host(error)
        }
        if let error = error as? RuntimeAdapterFailure {
            return .host(.adapterFailure(error.kind, error.diagnosticCode))
        }
        return .host(.adapterUnavailable)
    }

    private func throwRestoredResumeRaceFailure(
        _ failure: RuntimeRestoredResumeRaceFailure,
    ) throws -> Never {
        switch failure {
        case .cancellation:
            throw CancellationError()
        case .attemptLost:
            throw RuntimeHostError.persistenceConflict
        case let .host(error):
            throw error
        case .terminalEventPersistence:
            throw RuntimeTerminalEventPersistenceError.persistenceFailure
        case .heartbeatPersistence:
            throw RuntimeRestorationHeartbeatPersistenceError.persistenceFailure
        case .providerTerminalAdmission:
            throw RuntimeProviderTerminalAdmissionError.rejected
        }
    }

    private func restorationHeartbeatResult(
        host: ExternalAgentSessionReference,
        receipt: RuntimeLaunchReceipt,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult {
        while true {
            try await restorationClock.sleep(restorationHeartbeatInterval)
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: receipt.runReference,
            )
            do {
                try await renewRestorationClaim(
                    host,
                    runReference: receipt.runReference,
                    lease: lease,
                    restoredContext: restoredContext,
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
                        restoredContext: restoredContext,
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
                    restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RuntimeResult? {
        if error is CancellationError { throw CancellationError() }
        do {
            if let terminal = storedTerminalResult(host: host, runReference: runReference) {
                return terminal
            }
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: runReference,
            )
            if let terminal = try await persistedTerminalResult(
                host: host,
                runReference: runReference,
                restoredContext: restoredContext,
            ) {
                return terminal
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeHostError {
            throw error
        } catch is RuntimeRestoredResumeAttemptError {
            throw RuntimeRestoredResumeAttemptError.lost
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
        restoredContext: RuntimeRestoredResumeContext,
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
                    restoredContext: restoredContext,
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
                        restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws {
        try requireRestoredResumeContext(
            restoredContext,
            host: host,
            runReference: runReference,
        )
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
                    restoredContext: restoredContext,
                )
            } catch RuntimeHostError.persistenceConflict {
                try await repairRestorationClaimAfterConflict(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                    restoredContext: restoredContext,
                )
            }
        case .restoreClaim:
            try await recoverRestorationClaimAfterExpiry(
                host: host,
                runReference: runReference,
                lease: lease,
                now: now,
                restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws {
        if let restoredContext {
            try requireRestoredResumeContext(
                restoredContext,
                host: host,
                runReference: runReference,
            )
        }
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
                    restoredContext: restoredContext,
                )
                if let restoredContext {
                    invalidateRestoredResumeAttempt(restoredContext.attemptID, host: host)
                }
            } catch RuntimeHostError.persistenceConflict {
                try await restoreResumptionClaimIfNeeded(
                    host,
                    lease: lease,
                    fencePersistedOwner: true,
                )
            } catch {
                applyCleanupFailedDecision(host: host, runReference: runReference)
                deactivateLocalResumptionLeaseIfOwned(
                    host: host,
                    runReference: runReference,
                    lease: lease,
                )
                throw error
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws {
        _ = try await commit(host: host) { plane, registry in
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                    in: registry,
                )
            }
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws {
        let decision = try await reconcileRestorationClaimAfterConflict(
            host: host,
            runReference: runReference,
            lease: lease,
            restoredContext: restoredContext,
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
                restoredContext: restoredContext,
            )
        } catch RuntimeHostError.persistenceConflict {
            _ = try await reconcileRestorationClaimAfterConflict(
                host: host,
                runReference: runReference,
                lease: lease,
                restoredContext: restoredContext,
            )
            throw RuntimeHostError.persistenceConflict
        }
    }

    private func reconcileRestorationClaimAfterConflict(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> RuntimeRestoreResumeDecisionTable.Decision {
        try await withPersistedState { plane, loaded in
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                )
            }
            guard let loaded else { throw RuntimeHostError.persistenceConflict }
            let expectedStored = plane.sessions[host]?.stored
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                )
            }
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
        restoredContext: RuntimeRestoredResumeContext,
    ) async throws -> RestoredConsumptionResult {
        do {
            if let terminal = try await interruptAfterConsumptionFailure(
                receipt: receipt,
                host: hostReference,
                lease: lease,
                restoredContext: restoredContext,
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
        activeRestoredResumeAttempts.removeValue(forKey: hostReference)
        if shouldFencePersistedOwner {
            let expectedRunReference = sessions[hostReference]?.stored.runReference
            let hasPersistedOwner = try await fencePersistedOwner(hostReference, lease: lease)
            if !hasPersistedOwner, let expectedRunReference {
                deactivateLocalResumptionLeaseIfOwned(
                    host: hostReference,
                    runReference: expectedRunReference,
                    lease: lease,
                )
            }
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
        // 호출자가 이미 취소된 경우에도 복구 저장은 반드시 반영되어야 한다(비구조 태스크로 취소 전파 차단).
        try await Task { [self] in
            try await mutateAfterPersistedTransitions { plane in
                plane.restoreLocalResumptionClaimIfNeeded(hostReference, lease: lease)
            }
        }.value
    }

    private func fencePersistedOwner(
        _ hostReference: ExternalAgentSessionReference,
        lease: UInt64,
        runReference: RuntimeRunReference? = nil,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> Bool {
        try await withPersistedState { plane, loaded in
            if let restoredContext, let runReference {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: hostReference,
                    runReference: runReference,
                )
            }
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
                if let restoredContext {
                    guard plane.activeRestoredResumeAttempts[hostReference] == restoredContext.attemptID,
                          expectedSession?.stored.runReference == runReference,
                          expectedSession?.lease == .resuming(restoredContext.lease)
                    else { throw RuntimeRestoredResumeAttemptError.lost }
                }
                plane.sessions[hostReference] = adopted
                plane.finalizeVisibleResumptionTerminal(
                    host: hostReference,
                    runReference: runReference,
                    lease: lease,
                    restoredContext: restoredContext,
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
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws {
        try await commit(host: host) { plane, registry in
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: runReference,
                    in: registry,
                )
            }
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

private enum RuntimeRestoredResumeRaceOutcome {
    case result(RuntimeResult)
    case failure(RuntimeRestoredResumeRaceFailure)
    case cancelled
}

private enum RuntimeRestoredResumeRaceFailure {
    case cancellation
    case attemptLost
    case host(RuntimeHostError)
    case terminalEventPersistence
    case heartbeatPersistence
    case providerTerminalAdmission
}

extension RuntimeRestoredResumeRaceOutcome: Sendable {}
extension RuntimeRestoredResumeRaceFailure: Sendable {}

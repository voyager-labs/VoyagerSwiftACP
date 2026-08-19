import Foundation

private enum ConsumedOutcome {
    case terminal(RuntimeResult)
    case result(RuntimeResult)
}

extension RuntimeControlPlane {
    public func run(_ request: RuntimeLaunchRequest) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        if try await retireOrphanedDirectRunIfNeeded(request) {
            throw RuntimeHostError.duplicateRunReference
        }
        let reservation = try await commit(host: request.externalAgentSessionReference) { plane, registry in
            try plane.reserveTransition(request, in: &registry)
        }
        let receipt: RuntimeLaunchReceipt
        do {
            receipt = try await reservation.adapter.launch(request)
        } catch is CancellationError {
            try await propagateLaunchCancellation(host: reservation.host, lease: reservation.lease)
        } catch {
            return try await resolveLaunchFailure(
                error,
                reservation: reservation,
                runReference: request.runReference,
            )
        }
        let receiptTransition = try await recordReceipt(
            receipt,
            request: request,
            reservation: reservation,
        )
        return try await finishReceipt(
            receipt,
            reservation: reservation,
            transition: receiptTransition,
        )
    }

    private func recordReceipt(
        _ receipt: RuntimeLaunchReceipt,
        request: RuntimeLaunchRequest,
        reservation: RunReservation,
    ) async throws -> ReceiptTransition {
        do {
            return try await commit(host: reservation.host) { plane, registry in
                try plane.recordReceiptTransition(
                    receipt,
                    request: request,
                    descriptor: reservation.descriptor,
                    lease: reservation.lease,
                    in: &registry,
                )
            }
        } catch RuntimeHostError.persistenceFailure {
            try? await reconcileStartedProviderFailure(reservation: reservation, receipt: receipt)
            throw RuntimeHostError.persistenceFailure
        } catch RuntimeHostError.persistenceConflict {
            return try await resolveReceiptConflict(receipt, request: request, reservation: reservation)
        } catch {
            try? await reconcileStartedProviderFailure(
                reservation: reservation,
                receipt: receipt,
            )
            throw error
        }
    }

    private func resolveReceiptConflict(
        _ receipt: RuntimeLaunchReceipt,
        request: RuntimeLaunchRequest,
        reservation: RunReservation,
    ) async throws -> ReceiptTransition {
        if try await persistedTerminalResult(
            host: reservation.host,
            runReference: receipt.runReference,
        ) != nil {
            do {
                return try await commit(host: reservation.host) { plane, registry in
                    try plane.recordReceiptTransition(
                        receipt,
                        request: request,
                        descriptor: reservation.descriptor,
                        lease: reservation.lease,
                        in: &registry,
                    )
                }
            } catch RuntimeHostError.persistenceConflict {
                return try await reconcileReceiptRetryConflict(receipt, reservation: reservation)
            }
        }
        do {
            try await reconcileStartedProviderFailure(reservation: reservation, receipt: receipt)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
        throw RuntimeHostError.persistenceConflict
    }

    private func reconcileReceiptRetryConflict(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
    ) async throws -> ReceiptTransition {
        let terminal = try await withPersistedState { plane, loaded in
            let persisted = loaded ?? RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: [],
            )
            plane.sessions = plane.reconciledRegistry(candidate: plane.sessions, persisted: persisted)
            try Task.checkCancellation()
            return plane.storedTerminalResult(
                host: reservation.host,
                runReference: receipt.runReference,
            )
        }
        try await reconcileStartedProviderFailure(reservation: reservation, receipt: receipt)
        try Task.checkCancellation()
        guard let terminal else { throw RuntimeHostError.persistenceConflict }
        return .terminal(terminal)
    }

    private func finishReceipt(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        transition: ReceiptTransition,
    ) async throws -> RuntimeResult {
        switch transition {
        case let .terminal(result):
            result
        case let .consuming(lease):
            try await consumeAndFinish(receipt, reservation: reservation, lease: lease)
        }
    }

    private func propagateLaunchCancellation(
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> Never {
        await detachLaunchOwner(host: host, lease: lease)
        throw CancellationError()
    }

    private func detachLaunchOwner(host: ExternalAgentSessionReference, lease: UInt64) async {
        try? await mutateAfterPersistedTransitions { plane in
            plane.detachLaunchOwnerTransition(host: host, lease: lease)
        }
    }

    private func resolveLaunchFailure(
        _ error: any Error,
        reservation: RunReservation,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult {
        let primary = normalizeAdapterError(error)
        do {
            let terminal = try await commit(host: reservation.host, { plane, registry in
                plane.failLaunchTransition(
                    host: reservation.host,
                    lease: reservation.lease,
                    in: &registry,
                )
            })
            try Task.checkCancellation()
            if let terminal {
                return terminal
            }
        } catch {
            do {
                try Task.checkCancellation()
                if let terminal = try await persistedTerminalResult(
                    host: reservation.host,
                    runReference: runReference,
                ), let reconciled = try await reconcileLaunchFailureTerminal(
                    terminal,
                    host: reservation.host,
                    runReference: runReference,
                    lease: reservation.lease,
                ) {
                    try Task.checkCancellation()
                    return reconciled
                }
            } catch is CancellationError {
                await detachLaunchOwner(host: reservation.host, lease: reservation.lease)
                throw CancellationError()
            } catch {
                // 원래 adapter 오류를 우선하기 위해 fallback persistence 오류는 무시한다.
            }
        }
        throw primary
    }

    private func reconcileLaunchFailureTerminal(
        _ terminal: RuntimeResult,
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        try await mutateAfterPersistedTransitions { plane in
            guard var session = plane.sessions[host],
                  session.stored.runReference == runReference,
                  session.lease == .launching(lease),
                  session.stored.projection.isTerminal
            else { return nil }
            session.lease = .none
            session.revision += 1
            plane.sessions[host] = session
            return terminal
        }
    }

    private func consumeAndFinish(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        switch try await consumeWithCleanup(receipt, reservation: reservation, lease: lease) {
        case let .terminal(result):
            result
        case let .result(result):
            try await finishConsumedResult(result, host: reservation.host, lease: lease)
        }
    }

    private func consumeWithCleanup(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        do {
            return try await .result(consume(receipt, from: reservation.adapter, host: reservation.host))
        } catch RuntimeTerminalEventPersistenceError.persistenceFailure {
            try? await recoverTerminalPersistenceClaim(host: reservation.host, lease: lease)
            throw RuntimeHostError.persistenceFailure
        } catch is CancellationError {
            try? await detachConsumerOwner(host: reservation.host, lease: lease)
            throw CancellationError()
        } catch {
            let primary = (error as? RuntimeHostError) ?? normalizeAdapterError(error)
            if let terminal = try await interruptAfterConsumptionFailure(
                receipt: receipt,
                host: reservation.host,
                lease: lease,
            ) { return .terminal(terminal) }
            throw primary
        }
    }

    private func interruptAfterConsumptionFailure(
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        do {
            _ = try await commit(host: host) { plane, registry in
                try plane.interruptTransition(host: host, lease: lease, in: &registry)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch RuntimeHostError.persistenceConflict {
            if let terminal = try await reconcileInterruptedConsumptionConflict(
                host: host,
                runReference: receipt.runReference,
                lease: lease,
            ) {
                return terminal
            }
            throw RuntimeHostError.persistenceConflict
        } catch let cleanupError as RuntimeHostError {
            throw cleanupError
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
        return nil
    }

    private func finishConsumedResult(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        if let terminal = try await reconcileConsumedResult(result, host: host, lease: lease) {
            return terminal
        }
        do {
            return try await persistTerminalResult(result, host: host, lease: lease)
        } catch {
            try? await recoverTerminalPersistenceClaim(host: host, lease: lease)
            throw error
        }
    }

    private func reconcileInterruptedConsumptionConflict(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        guard let terminal = try await persistedTerminalResult(host: host, runReference: runReference) else {
            return nil
        }
        return try await reconcileConsumedResult(terminal, host: host, lease: lease)
    }

    func reconcileConsumedResult(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult? {
        try await mutateAfterPersistedTransitions { plane in
            guard var session = plane.sessions[host],
                  session.stored.runReference == result.runReference,
                  session.lease == .consuming(lease) || session.lease == .resuming(lease),
                  let terminal = plane.terminalResult(for: session.stored)
            else { return nil }
            session.lease = .none
            session.revision += 1
            plane.sessions[host] = session
            return terminal.outcome == result.outcome ? result : terminal
        }
    }

    func detachConsumerOwner(
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws {
        try await mutateAfterPersistedTransitions { plane in
            plane.detachConsumerOwnerTransition(host: host, lease: lease, in: &plane.sessions)
        }
    }

    func recoverTerminalPersistenceClaim(
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws {
        try await mutateAfterPersistedTransitions { plane in
            plane.recoverTerminalPersistenceClaimTransition(host: host, lease: lease)
        }
    }

    func persistTerminalResult(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        do {
            let terminal = try await commit(host: host) { plane, registry in
                try plane.finishTransition(result, host: host, lease: lease, in: &registry)
            }
            try Task.checkCancellation()
            return terminal
        } catch RuntimeHostError.persistenceConflict {
            try Task.checkCancellation()
            if try await persistedTerminalResult(host: host, runReference: result.runReference) != nil,
               let terminal = try await reconcileConsumedResult(result, host: host, lease: lease)
            {
                try Task.checkCancellation()
                return terminal
            }
            do {
                let terminal = try await commit(host: host) { plane, registry in
                    try plane.finishTransition(result, host: host, lease: lease, in: &registry)
                }
                try Task.checkCancellation()
                return terminal
            } catch RuntimeHostError.persistenceConflict {
                try Task.checkCancellation()
                if try await persistedTerminalResult(host: host, runReference: result.runReference) != nil,
                   let terminal = try await reconcileConsumedResult(result, host: host, lease: lease)
                {
                    try Task.checkCancellation()
                    return terminal
                }
                throw RuntimeHostError.persistenceFailure
            }
        }
    }

    private func reconcileStartedProviderFailure(
        reservation: RunReservation,
        receipt: RuntimeLaunchReceipt? = nil,
    ) async throws {
        do {
            try await persistStartedProviderFailure(reservation: reservation, receipt: receipt)
        } catch RuntimeHostError.persistenceConflict {
            do {
                try await persistStartedProviderFailure(reservation: reservation, receipt: receipt)
            } catch RuntimeHostError.persistenceConflict {
                try await synchronizePersistedRegistry(
                    releasingTerminalLaunchFor: reservation,
                    receipt: receipt,
                )
                throw RuntimeHostError.persistenceConflict
            }
        }
    }

    private func synchronizePersistedRegistry(
        releasingTerminalLaunchFor reservation: RunReservation,
        receipt: RuntimeLaunchReceipt?,
    ) async throws {
        try await withPersistedState { plane, loaded in
            let persisted = loaded ?? RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: [],
            )
            plane.sessions = plane.reconciledRegistry(candidate: plane.sessions, persisted: persisted)
            if let receipt,
               var session = plane.sessions[reservation.host],
               session.stored.runReference == receipt.runReference,
               session.stored.projection.isTerminal,
               session.lease == .launching(reservation.lease)
            {
                session.lease = .none
                session.revision += 1
                plane.sessions[reservation.host] = session
            }
            try Task.checkCancellation()
        }
    }

    private func persistStartedProviderFailure(
        reservation: RunReservation,
        receipt: RuntimeLaunchReceipt?,
    ) async throws {
        _ = try await commit(host: reservation.host) { plane, registry in
            try plane.interruptTransition(
                host: reservation.host,
                lease: reservation.lease,
                in: &registry,
                receipt: receipt,
            )
        }
    }
}

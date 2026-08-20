import Foundation

private enum ConsumedOutcome {
    case terminal(RuntimeResult)
    case result(RuntimeResult)
}

extension RuntimeControlPlane {
    public func run(_ request: RuntimeLaunchRequest) async throws -> RuntimeResult {
        try await hydrateIfNeeded()
        let reservationTransition: ReservationTransition
        do {
            reservationTransition = try await commit(host: request.externalAgentSessionReference) { plane, registry in
                try plane.reserveTransition(request, in: &registry)
            }
        } catch RuntimeHostError.persistenceConflict {
            try await reconcileReservationConflict(request)
            throw RuntimeHostError.persistenceConflict
        }
        let reservation: RunReservation
        switch reservationTransition {
        case let .reserved(value):
            reservation = value
        case .rejectedDuplicate:
            throw RuntimeHostError.duplicateRunReference
        }
        let receipt: RuntimeLaunchReceipt
        do {
            receipt = try await reservation.adapter.launch(request)
        } catch is CancellationError {
            try await propagateCallerCancellation(
                host: reservation.host,
                originatingRunReference: request.runReference,
            )
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

    private func reconcileReservationConflict(_ request: RuntimeLaunchRequest) async throws {
        try await withPersistedState { plane, loaded in
            guard let loaded else { return }
            let current = plane.sessions[request.externalAgentSessionReference]?.freshRunSnapshot()
            plane.sessions = plane.reconciledRegistry(candidate: plane.sessions, persisted: loaded)
            guard let persisted = plane.sessions[request.externalAgentSessionReference]?.freshRunSnapshot(),
                  persisted.runReference == request.runReference
            else { return }
            guard case .adoptPersisted = RuntimeFreshRunDecisionTable.decide(
                .persistConflict(persisted: persisted),
                on: current ?? persisted,
            ) else { return }
        }
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
        } catch is CancellationError {
            try await propagateCallerCancellation(
                host: reservation.host,
                originatingRunReference: receipt.runReference,
                receipt: receipt,
            )
        } catch RuntimeHostError.persistenceFailure {
            try? await reconcileStartedProviderFailure(reservation: reservation, receipt: receipt)
            throw RuntimeHostError.persistenceFailure
        } catch RuntimeHostError.persistenceConflict {
            do {
                return try await resolveReceiptConflict(receipt, request: request, reservation: reservation)
            } catch is CancellationError {
                try await propagateCallerCancellation(
                    host: reservation.host,
                    originatingRunReference: receipt.runReference,
                    receipt: receipt,
                )
            }
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
        guard let persisted = try await readRepairReceiptConflict(
            receipt,
            host: reservation.host,
        ) else {
            throw RuntimeHostError.persistenceConflict
        }

        if persisted.projection.isTerminal {
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
                if let terminal = try await readRepairPersistedHostTerminal(host: reservation.host) {
                    guard terminal.runReference == receipt.runReference else {
                        throw RuntimeHostError.persistenceConflict
                    }
                    return .terminal(terminal)
                }
                throw RuntimeHostError.persistenceConflict
            }
        }

        do {
            try await reconcileStartedProviderFailure(reservation: reservation, receipt: receipt)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            applyCleanupFailedDecision(host: reservation.host, runReference: receipt.runReference)
            throw RuntimeHostError.persistenceConflict
        }
        throw RuntimeHostError.persistenceConflict
    }

    private func readRepairReceiptConflict(
        _ receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeFreshRunSnapshot? {
        try await withPersistedState { plane, loaded in
            let current = plane.sessions[host]?.freshRunSnapshot()
            guard let loaded else { return nil }
            guard let stored = loaded.sessions.first(where: {
                $0.externalAgentSessionReference == host
                    && $0.runReference == receipt.runReference
            }) else { return nil }
            let expectedSession = plane.sessions[host]
            let adopted = Session(
                stored: stored,
                lease: expectedSession?.lease ?? .none,
                revision: expectedSession?.revision ?? 0,
            )
            plane.sessions[host] = adopted
            let persisted = adopted.freshRunSnapshot()
            guard case .adoptPersisted = RuntimeFreshRunDecisionTable.decide(
                .persistConflict(persisted: persisted),
                on: current ?? persisted,
            ) else { return nil }
            return persisted
        }
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

    private func propagateCallerCancellation(
        host: ExternalAgentSessionReference,
        originatingRunReference: RuntimeRunReference,
        receipt: RuntimeLaunchReceipt? = nil,
    ) async throws -> Never {
        let persistence = Task.detached { [self] in
            try await commit(host: host) { plane, registry in
                try plane.persistCallerCancellationTransition(
                    host: host,
                    originatingRunReference: originatingRunReference,
                    in: &registry,
                    receipt: receipt,
                )
            }
        }
        _ = await persistence.result
        throw CancellationError()
    }

    private func resolveLaunchFailure(
        _ error: any Error,
        reservation: RunReservation,
        runReference: RuntimeRunReference,
    ) async throws -> RuntimeResult {
        let primary = normalizeAdapterError(error)
        do {
            let terminal = try await commit(host: reservation.host, { plane, registry in
                try plane.persistLaunchFailureTransition(
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
                try await propagateCallerCancellation(
                    host: reservation.host,
                    originatingRunReference: runReference,
                )
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
            try await finishConsumedResult(
                result,
                receipt: receipt,
                host: reservation.host,
                lease: lease,
            )
        }
    }

    private func consumeWithCleanup(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        do {
            let result = try await consume(receipt, from: reservation.adapter, host: reservation.host)
            if let terminal = storedTerminalResult(
                host: reservation.host,
                runReference: receipt.runReference,
            ) {
                return .terminal(terminal.outcome == result.outcome ? result : terminal)
            }
            return .result(result)
        } catch RuntimeHostError.persistenceConflict {
            try? await recoverTerminalPersistenceClaim(host: reservation.host, lease: lease)
            throw RuntimeHostError.persistenceConflict
        } catch RuntimeProviderTerminalAdmissionError.rejected {
            try? await recoverTerminalPersistenceClaim(host: reservation.host, lease: lease)
            throw RuntimeHostError.invalidEvent
        } catch is CancellationError {
            try await propagateCallerCancellation(
                host: reservation.host,
                originatingRunReference: receipt.runReference,
                receipt: receipt,
            )
        } catch {
            let primary = (error as? RuntimeHostError) ?? normalizeAdapterError(error)
            do {
                if let terminal = try await interruptAfterConsumptionFailure(
                    receipt: receipt,
                    host: reservation.host,
                    lease: lease,
                ) { return .terminal(terminal) }
            } catch {
                applyCleanupFailedDecision(host: reservation.host, runReference: receipt.runReference)
            }
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
            if let terminal = try await readRepairPersistedTerminal(
                host: host,
                runReference: receipt.runReference,
            ) {
                return try await reconcileConsumedResult(terminal, host: host, lease: lease)
            }
            throw RuntimeHostError.persistenceConflict
        }
        return nil
    }

    private func finishConsumedResult(
        _ result: RuntimeResult,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        if let terminal = try await reconcileConsumedResult(result, host: host, lease: lease) {
            return terminal
        }
        do {
            return try await persistTerminalResult(result, host: host, lease: lease)
        } catch is CancellationError {
            try await propagateCallerCancellation(
                host: host,
                originatingRunReference: receipt.runReference,
                receipt: receipt,
            )
        } catch {
            try? await recoverTerminalPersistenceClaim(host: host, lease: lease)
            throw error
        }
    }

    private func applyCleanupFailedDecision(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) {
        guard let session = sessions[host], session.stored.runReference == runReference else { return }
        _ = RuntimeFreshRunDecisionTable.decide(
            .cleanupFailed,
            on: session.freshRunSnapshot(),
        )
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
            return try await repairTerminalResultAfterConflict(result, host: host, lease: lease)
        }
    }

    private func repairTerminalResultAfterConflict(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        if try await readRepairPersistedTerminal(host: host, runReference: result.runReference) != nil,
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
            if try await readRepairPersistedTerminal(host: host, runReference: result.runReference) != nil,
               let terminal = try await reconcileConsumedResult(result, host: host, lease: lease)
            {
                try Task.checkCancellation()
                return terminal
            }
            throw RuntimeHostError.persistenceConflict
        }
    }

    private func reconcileStartedProviderFailure(
        reservation: RunReservation,
        receipt: RuntimeLaunchReceipt,
    ) async throws {
        do {
            try await persistStartedProviderFailure(reservation: reservation, receipt: receipt)
        } catch RuntimeHostError.persistenceConflict {
            _ = try? await readRepairPersistedHostTerminal(host: reservation.host)
            throw RuntimeHostError.persistenceConflict
        }
    }

    private func readRepairPersistedHostTerminal(
        host: ExternalAgentSessionReference,
    ) async throws -> RuntimeResult? {
        try await withPersistedState { plane, loaded in
            guard let loaded,
                  let stored = loaded.sessions.first(where: {
                      $0.externalAgentSessionReference == host
                  }),
                  let terminal = plane.terminalResult(for: stored)
            else { return nil }
            let current = plane.sessions[host]?.freshRunSnapshot()
            let persisted = Session(stored: stored).freshRunSnapshot()
            guard case .adoptPersisted = RuntimeFreshRunDecisionTable.decide(
                .persistConflict(persisted: persisted),
                on: current ?? persisted,
            ) else { return nil }
            plane.sessions[host] = Session(
                stored: stored,
                lease: .none,
                revision: plane.sessions[host]?.revision ?? 0,
            )
            return terminal
        }
    }

    private func persistStartedProviderFailure(
        reservation: RunReservation,
        receipt: RuntimeLaunchReceipt,
    ) async throws {
        _ = try await commit(host: reservation.host) { plane, registry in
            try plane.persistReceiptFailureTransition(
                host: reservation.host,
                lease: reservation.lease,
                receipt: receipt,
                in: &registry,
            )
        }
    }
}

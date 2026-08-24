import Foundation

private enum ConsumedOutcome {
    case terminal(RuntimeResult)
    case result(RuntimeResult)
}

/// fresh 소비 경합의 단발 결과. provider 태스크가 유일한 생산자다.
private enum FreshProviderRaceOutcome {
    case consumed(RuntimeResult)
    case failed(FreshConsumptionFailure)
}

/// provider 소비 실패를 caller 취소 재분류 없이 운반하기 위한 Sendable 래퍼다.
private enum FreshConsumptionFailure: Error {
    case cancellation
    case admissionRejected
    case host(RuntimeHostError)
}

/// provider 단발 결과 우편함이다. caller 취소가 AsyncStream처럼 채널 자체를 마무리하지
/// 않도록 actor로 유지하고, 결과를 정확히 한 명의 소비자에게만 전달한다.
private actor FreshProviderRaceMailbox {
    private var storedOutcome: FreshProviderRaceOutcome?
    private var waiter: CheckedContinuation<FreshProviderRaceOutcome?, Never>?

    /// provider 태스크가 유일한 생산자다. 대기자가 없으면 결과를 보관한다.
    func deliver(_ outcome: FreshProviderRaceOutcome) {
        if let waiter {
            waiter.resume(returning: outcome)
            self.waiter = nil
        } else {
            storedOutcome = outcome
        }
    }

    /// caller 대기다. 취소 시 nil로 재개되지만 보관된 결과는 채널에 남아 배경 드레인이 받는다.
    func awaitOutcome() async -> FreshProviderRaceOutcome? {
        if let storedOutcome { return storedOutcome }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<FreshProviderRaceOutcome?, Never>) in
                install(continuation)
            }
        }, onCancel: {
            Task { await cancelWaiter() }
        })
    }

    /// 배경 드레인 대기다. 취소되지 않는 태스크 전용이며 결과 도착까지 반환하지 않는다.
    func awaitOutcomeForAbandonedConvergence() async -> FreshProviderRaceOutcome? {
        if let storedOutcome { return storedOutcome }
        return await withCheckedContinuation { (continuation: CheckedContinuation<FreshProviderRaceOutcome?, Never>) in
            install(continuation)
        }
    }

    private func install(_ continuation: CheckedContinuation<FreshProviderRaceOutcome?, Never>) {
        // 등록 경합에서 결과가 먼저 도착했으면 즉시 재개한다.
        if let storedOutcome {
            continuation.resume(returning: storedOutcome)
        } else {
            waiter = continuation
        }
    }

    private func cancelWaiter() {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: nil)
    }
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
            cleanupFailureEvidenceByHost.removeValue(forKey: reservation.host)
        case .rejectedDuplicate:
            throw RuntimeHostError.duplicateRunReference
        }
        let receipt: RuntimeLaunchReceipt
        do {
            try Task.checkCancellation()
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
                originatingRunReference: request.runReference,
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
        } catch RuntimeHostError.malformedAdapterResponse {
            detachTrustedLaunchOwner(
                host: reservation.host,
                runReference: request.runReference,
                lease: reservation.lease,
            )
            throw RuntimeHostError.malformedAdapterResponse
        } catch {
            try? await reconcileStartedProviderFailure(
                reservation: reservation,
                receipt: receipt,
            )
            throw error
        }
    }

    private func detachTrustedLaunchOwner(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) {
        guard var session = sessions[host],
              session.stored.runReference == runReference,
              session.lease == .launching(lease)
        else { return }
        session.lease = session.stored.projection.isTerminal ? .none : .detachedLaunching(lease)
        session.revision += 1
        sessions[host] = session
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
            }) else { return nil }
            guard stored.runReference == receipt.runReference else {
                plane.sessions = plane.reconciledRegistry(candidate: plane.sessions, persisted: loaded)
                return nil
            }
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
            // terminal 수렴 계약: caller 취소와 무관하게 저장된 결과를 그대로 반환한다.
            return result
        case let .consuming(lease):
            // receipt 저장 이후 최초 취소 관찰 지점: provider 소비 시작 전에 canonical detachment로 탈출한다.
            guard !Task.isCancelled else {
                try await propagateCallerCancellation(
                    host: reservation.host,
                    originatingRunReference: receipt.runReference,
                    receipt: receipt,
                )
            }
            return try await consumeAndFinish(receipt, reservation: reservation, lease: lease)
        }
    }

    private func propagateCallerCancellation(
        host: ExternalAgentSessionReference,
        originatingRunReference: RuntimeRunReference,
        receipt: RuntimeLaunchReceipt? = nil,
    ) async throws -> Never {
        // canonical detachment는 caller 취소와 무관하게 반영된다.
        await persistCallerCancellationDetachment(
            host: host,
            originatingRunReference: originatingRunReference,
            receipt: receipt,
        )
        throw CancellationError()
    }

    private func persistCallerCancellationDetachment(
        host: ExternalAgentSessionReference,
        originatingRunReference: RuntimeRunReference,
        receipt: RuntimeLaunchReceipt? = nil,
    ) async {
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
        if case .failure = await persistence.result {
            await recoverCallerCancellationPersistenceFailure(
                host: host,
                originatingRunReference: originatingRunReference,
            )
        }
    }

    private func recoverCallerCancellationPersistenceFailure(
        host: ExternalAgentSessionReference,
        originatingRunReference: RuntimeRunReference,
    ) async {
        applyCleanupFailedDecision(
            host: host,
            runReference: originatingRunReference,
        )
        try? await mutateAfterPersistedTransitions { plane in
            guard var session = plane.sessions[host],
                  session.stored.runReference == originatingRunReference
            else { return }
            switch session.lease {
            case let .launching(lease):
                session.lease = session.stored.projection.isTerminal ? .none : .detachedLaunching(lease)
            case let .consuming(lease):
                session.lease = session.stored.projection.isTerminal ? .none : .detachedConsuming(lease)
            case .none, .detachedLaunching, .detachedConsuming, .restored, .resuming:
                return
            }
            session.revision += 1
            plane.sessions[host] = session
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
        let outcome = try await consumeWithCleanup(receipt, reservation: reservation, lease: lease)
        return try await finishConsumedOutcome(outcome, receipt: receipt, host: reservation.host, lease: lease)
    }

    private func finishConsumedOutcome(
        _ outcome: ConsumedOutcome,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> RuntimeResult {
        switch outcome {
        case let .terminal(result):
            result
        case let .result(result):
            try await finishConsumedResult(
                result,
                receipt: receipt,
                host: host,
                lease: lease,
            )
        }
    }

    private func consumeWithCleanup(
        _ receipt: RuntimeLaunchReceipt,
        reservation: RunReservation,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        // 단일 provider 소비를 비구조 태스크에서 실행해 caller 취소와 경합한다.
        // provider 태스크는 우편함의 유일한 생산자로 결과를 정확히 한 번 전달한다.
        let mailbox = FreshProviderRaceMailbox()
        let providerTask = Task { [self] in
            do {
                let result = try await consume(
                    receipt,
                    from: reservation.adapter,
                    host: reservation.host,
                )
                await mailbox.deliver(.consumed(result))
            } catch {
                await mailbox.deliver(.failed(freshConsumptionFailure(error)))
            }
        }
        _ = providerTask
        switch await mailbox.awaitOutcome() {
        case let .some(.consumed(result)):
            // provider 결과가 이기면 늦은 취소와 무관하게 수렴 결과를 그대로 처리한다.
            return try await reconcileConsumedOutcome(
                result,
                receipt: receipt,
                host: reservation.host,
                lease: lease,
            )
        case let .some(.failed(failure)):
            return try await recoverConsumptionFailure(
                failure,
                receipt: receipt,
                host: reservation.host,
                lease: lease,
            )
        case .none:
            // nil은 caller 취소 재개뿐이다. 탈출 경계로 분류해 배경 수렴을 남긴다.
            guard Task.isCancelled else { throw RuntimeHostError.invalidEvent }
            return try await convergeOrEscapeOnCallerCancellation(
                mailbox: mailbox,
                receipt: receipt,
                host: reservation.host,
                lease: lease,
            )
        }
    }

    /// caller 취소 경계다. 저장된 단말이 이미 있으면 취소와 무관하게 수렴 결과를 반환하고,
    /// 아니면 canonical detachment와 배경 수렴을 남긴 뒤 탈출한다.
    private func convergeOrEscapeOnCallerCancellation(
        mailbox: FreshProviderRaceMailbox,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        if let terminal = storedTerminalResult(host: host, runReference: receipt.runReference) {
            try? await releaseConsumedTerminalOwner(
                host: host,
                runReference: receipt.runReference,
                lease: lease,
            )
            return .terminal(terminal)
        }
        await persistCallerCancellationDetachment(
            host: host,
            originatingRunReference: receipt.runReference,
            receipt: receipt,
        )
        spawnAbandonedProviderConvergence(
            mailbox: mailbox,
            receipt: receipt,
            host: host,
            lease: lease,
        )
        throw CancellationError()
    }

    /// provider 소비 결과의 저장 단말 우선권과 소유권 해제를 검증한다(기존 fast-path 계약 유지).
    private func reconcileConsumedOutcome(
        _ result: RuntimeResult,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        if let terminal = storedTerminalResult(
            host: host,
            runReference: receipt.runReference,
        ) {
            // terminal 수렴 시 consuming 소유권 해제.
            try? await releaseConsumedTerminalOwner(
                host: host,
                runReference: receipt.runReference,
                lease: lease,
            )
            return .terminal(terminal.outcome == result.outcome ? result : terminal)
        }
        return .result(result)
    }

    /// provider 소비 실패를 기존 분류 경계로 처리한다(caller 취소 재분류 금지 유지).
    private func recoverConsumptionFailure(
        _ failure: FreshConsumptionFailure,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) async throws -> ConsumedOutcome {
        switch failure {
        case .cancellation:
            try await propagateCallerCancellation(
                host: host,
                originatingRunReference: receipt.runReference,
                receipt: receipt,
            )
        case .admissionRejected:
            try? await recoverTerminalPersistenceClaim(host: host, lease: lease)
            throw RuntimeHostError.invalidEvent
        case .host(.persistenceConflict):
            try? await recoverTerminalPersistenceClaim(host: host, lease: lease)
            throw RuntimeHostError.persistenceConflict
        case let .host(error):
            do {
                _ = try await interruptAfterConsumptionFailure(
                    receipt: receipt,
                    host: host,
                    lease: lease,
                )
            } catch is CancellationError {
                try await propagateCallerCancellation(
                    host: host,
                    originatingRunReference: receipt.runReference,
                    receipt: receipt,
                )
            } catch {
                applyCleanupFailedDecision(host: host, runReference: receipt.runReference)
                try? await recoverTerminalPersistenceClaim(host: host, lease: lease)
            }
            throw error
        }
    }

    private func freshConsumptionFailure(_ error: any Error) -> FreshConsumptionFailure {
        if error is CancellationError { return .cancellation }
        if error is RuntimeProviderTerminalAdmissionError { return .admissionRejected }
        if let error = error as? RuntimeHostError { return .host(error) }
        if let error = error as? RuntimeAdapterFailure {
            return .host(.adapterFailure(error.kind, error.diagnosticCode))
        }
        return .host(.adapterUnavailable)
    }

    /// caller 탈출 뒤 provider 수렴을 배경에서 완주하는 취소 중립 드레인이다.
    /// 탈출을 막지 않도록 기다리지 않고, 배경 실패는 기존 cleanup 증거 경계를 따른다.
    /// 우편함은 caller 취소로 마무리되지 않으므로 드레인이 결과를 정확히 한 번 받는다.
    private func spawnAbandonedProviderConvergence(
        mailbox: FreshProviderRaceMailbox,
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
    ) {
        Task { [self] in
            guard let outcome = await mailbox.awaitOutcomeForAbandonedConvergence() else { return }
            switch outcome {
            case let .consumed(result):
                // caller는 이미 CancellationError로 탈출했다. 배경 수렴은 최선 노력이다.
                guard let consumed = try? await reconcileConsumedOutcome(
                    result,
                    receipt: receipt,
                    host: host,
                    lease: lease,
                ) else { return }
                _ = try? await finishConsumedOutcome(
                    consumed,
                    receipt: receipt,
                    host: host,
                    lease: lease,
                )
            case let .failed(failure):
                _ = try? await recoverConsumptionFailure(failure, receipt: receipt, host: host, lease: lease)
            }
        }
    }

    func interruptAfterConsumptionFailure(
        receipt: RuntimeLaunchReceipt,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> RuntimeResult? {
        do {
            _ = try await commit(host: host) { plane, registry in
                try plane.interruptTransition(
                    host: host,
                    lease: lease,
                    in: &registry,
                    restoredContext: restoredContext,
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch RuntimeHostError.persistenceConflict {
            if let terminal = try await readRepairPersistedTerminal(
                host: host,
                runReference: receipt.runReference,
                restoredContext: restoredContext,
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

    func applyCleanupFailedDecision(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
    ) {
        guard let session = sessions[host], session.stored.runReference == runReference else { return }
        guard case .recordCleanupFailure = RuntimeFreshRunDecisionTable.decide(
            .cleanupFailed,
            on: session.freshRunSnapshot(),
        ) else { return }
        cleanupFailureEvidenceByHost[host] = RuntimeCleanupFailureEvidence(
            runReference: runReference,
            kind: .persistence,
        )
    }

    func reconcileConsumedResult(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> RuntimeResult? {
        try await mutateAfterPersistedTransitions { plane in
            if let restoredContext {
                try plane.requireRestoredResumeContext(
                    restoredContext,
                    host: host,
                    runReference: result.runReference,
                )
            }
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

    private func releaseConsumedTerminalOwner(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        lease: UInt64,
    ) async throws {
        // caller 취소가 persistence waiter를 탈출시켜도 terminal 소유권 해제는 반드시 반영된다.
        try await Task { [self] in
            try await mutateAfterPersistedTransitions { plane in
                guard var session = plane.sessions[host],
                      session.stored.runReference == runReference,
                      session.lease == .consuming(lease),
                      session.stored.projection.isTerminal
                else { return }
                session.lease = .none
                session.revision += 1
                plane.sessions[host] = session
            }
        }.value
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
        // caller 취소가 persistence waiter를 탈출시켜도 terminal claim 회수는 반드시 반영된다.
        try await Task { [self] in
            try await mutateAfterPersistedTransitions { plane in
                plane.recoverTerminalPersistenceClaimTransition(host: host, lease: lease)
            }
        }.value
    }

    func persistTerminalResult(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext? = nil,
    ) async throws -> RuntimeResult {
        do {
            let terminal = try await commit(host: host) { plane, registry in
                try plane.finishTransition(
                    result,
                    host: host,
                    lease: lease,
                    in: &registry,
                    restoredContext: restoredContext,
                )
            }
            try Task.checkCancellation()
            return terminal
        } catch RuntimeHostError.persistenceConflict {
            try Task.checkCancellation()
            return try await repairTerminalResultAfterConflict(
                result,
                host: host,
                lease: lease,
                restoredContext: restoredContext,
            )
        }
    }

    private func repairTerminalResultAfterConflict(
        _ result: RuntimeResult,
        host: ExternalAgentSessionReference,
        lease: UInt64,
        restoredContext: RuntimeRestoredResumeContext?,
    ) async throws -> RuntimeResult {
        if try await readRepairPersistedTerminal(
            host: host,
            runReference: result.runReference,
            restoredContext: restoredContext,
        ) != nil,
            let terminal = try await reconcileConsumedResult(
                result,
                host: host,
                lease: lease,
                restoredContext: restoredContext,
            )
        {
            try Task.checkCancellation()
            return terminal
        }
        do {
            let terminal = try await commit(host: host) { plane, registry in
                try plane.finishTransition(
                    result,
                    host: host,
                    lease: lease,
                    in: &registry,
                    restoredContext: restoredContext,
                )
            }
            try Task.checkCancellation()
            return terminal
        } catch RuntimeHostError.persistenceConflict {
            try Task.checkCancellation()
            if try await readRepairPersistedTerminal(
                host: host,
                runReference: result.runReference,
                restoredContext: restoredContext,
            ) != nil,
                let terminal = try await reconcileConsumedResult(
                    result,
                    host: host,
                    lease: lease,
                    restoredContext: restoredContext,
                )
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

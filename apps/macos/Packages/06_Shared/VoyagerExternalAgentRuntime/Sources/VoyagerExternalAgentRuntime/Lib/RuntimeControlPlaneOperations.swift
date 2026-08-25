import Foundation

public extension RuntimeControlPlane {
    func respondToApproval(
        hostReference: ExternalAgentSessionReference,
        requestID: RuntimeApprovalRequestID,
        operationID: RuntimeOperationID,
    ) async throws {
        guard requestID.isWithinRuntimeBounds, operationID.isWithinRuntimeBounds else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        let claim = try beginOperation(for: hostReference, requiring: .approval)
        let session = claim.session
        guard let providerReference = session.providerInternalSessionReference
        else { throw RuntimeHostError.malformedAdapterResponse }
        do {
            try Task.checkCancellation()
            try await claim.adapter.respondToApproval(RuntimeApprovalRequest(
                externalAgentSessionReference: hostReference,
                providerInternalSessionReference: providerReference,
                requestID: requestID,
                operationID: operationID,
                runReference: session.runReference,
                authorizationGeneration: session.storedContext.authorizationGeneration,
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw normalizeAdapterError(error)
        }
        try validateOperationClaim(claim, at: hostReference)
    }

    func enqueueInput(
        hostReference: ExternalAgentSessionReference,
        operationID: RuntimeOperationID,
        input: RuntimeSensitiveInput,
    ) async throws {
        guard operationID.isWithinRuntimeBounds,
              input.rawValue.unicodeScalars.count <= RuntimeBoundaryLimits.sensitiveInputScalars
        else { throw RuntimeHostError.malformedAdapterResponse }
        let claim = try beginOperation(for: hostReference, requiring: .queuedInput)
        do {
            try Task.checkCancellation()
            try await claim.adapter.enqueueInput(RuntimeQueuedInputRequest(
                operationID: operationID,
                runReference: claim.session.runReference,
                input: input,
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw normalizeAdapterError(error)
        }
        try validateOperationClaim(claim, at: hostReference)
    }

    func requestCancellation(
        hostReference: ExternalAgentSessionReference,
        operationID: RuntimeOperationID,
    ) async throws {
        guard operationID.isWithinRuntimeBounds else { throw RuntimeHostError.malformedAdapterResponse }
        let claim = try beginOperation(for: hostReference, requiring: .cancellation)
        do {
            try Task.checkCancellation()
            try await claim.adapter.requestCancellation(RuntimeCancellationRequest(
                operationID: operationID,
                runReference: claim.session.runReference,
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw normalizeAdapterError(error)
        }
        try validateOperationClaim(claim, at: hostReference)
    }

    func restore(
        hostReference: ExternalAgentSessionReference,
        expectedContext: RuntimeContextPolicy,
    ) async throws -> RuntimeRestoreResult {
        try await hydrateIfNeeded()
        guard let original = sessions[hostReference] else { return .stale }
        guard !original.lease.isActive else { throw RuntimeHostError.activeRunExists }
        let stored = original.stored
        guard !stored.projection.isTerminal else { return .stale }
        guard try evaluateRestore(original) else { return .stale }
        guard let providerInternalSessionReference = stored.providerInternalSessionReference,
              stored.storedContext == RuntimeStoredContext(contextPolicy: expectedContext),
              let adapter = adapters[stored.adapterID],
              stored.providerNamespace == adapter.descriptor.providerNamespace,
              stored.adapterVersion == adapter.descriptor.adapterVersion,
              stored.providerBranch == adapter.descriptor.providerBranch,
              stored.capabilitySnapshot == adapter.descriptor.capabilities
        else { return try await releaseStaleRestoreReservation(original, at: hostReference) }
        try await requireSameIdentityResumeOrRelease(original, at: hostReference)
        let binding = RuntimeRestartBinding(
            externalAgentSessionReference: stored.externalAgentSessionReference,
            providerInternalSessionReference: providerInternalSessionReference,
            runReference: stored.runReference,
            adapterID: stored.adapterID,
            providerNamespace: stored.providerNamespace,
            adapterVersion: stored.adapterVersion,
            providerBranch: stored.providerBranch,
            capabilitySnapshot: stored.capabilitySnapshot,
            contextPolicy: expectedContext,
        )
        let compatibility: RuntimeRestartCompatibility
        do {
            // 사전에 취소된 caller의 restore가 외부 호환성 확인을 시작하지 않도록 호출 전에 취소를 검사한다.
            try Task.checkCancellation()
            compatibility = try await adapter.restartCompatibility(for: binding)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw normalizeAdapterError(error)
        }
        guard sessionUnchanged(original, at: hostReference) else { return .stale }
        switch compatibility {
        case .compatible:
            return try await acquireRestoreClaim(original, at: hostReference)
        case .stale, .incompatible:
            return try await releaseStaleRestoreReservation(original, at: hostReference)
        }
    }

    private func evaluateRestore(_ session: Session) throws -> Bool {
        switch restoreDecision(.evaluateRestore, for: session) {
        case .stale:
            return false
        case .acquireClaim:
            return true
        case let .throwHost(error):
            throw error
        case .beginResume, .renewClaim, .restoreClaim, .adoptPersisted:
            throw RuntimeHostError.invalidEvent
        }
    }

    private func acquireRestoreClaim(
        _ original: Session,
        at host: ExternalAgentSessionReference,
    ) async throws -> RuntimeRestoreResult {
        do {
            return try await commit(host: host) { plane, registry in
                guard plane.sessionUnchanged(original, at: host, in: registry),
                      let current = registry[host]
                else { return .stale }
                switch plane.canAcquireRestorationClaim(current) {
                case .stale:
                    return .stale
                case .acquireClaim:
                    var replacement = current
                    replacement.stored = replacement.stored
                        .withRestorationClaim(plane.makeRestorationClaim())
                    _ = replacement.issueLease(RuntimeLease.restored)
                    registry[host] = replacement
                    return .restored
                case let .throwHost(error):
                    throw error
                case .beginResume, .renewClaim, .restoreClaim, .adoptPersisted:
                    throw RuntimeHostError.invalidEvent
                }
            }
        } catch RuntimeHostError.persistenceConflict {
            return try await reconcileRestoreClaimConflict(at: host)
        }
    }

    private func canAcquireRestorationClaim(
        _ session: Session,
    ) -> RuntimeRestoreResumeDecisionTable.Decision {
        restoreDecision(.acquireClaim, for: session)
    }

    private func restoreDecision(
        _ signal: RuntimeRestoreResumeDecisionTable.Signal,
        for session: Session,
    ) -> RuntimeRestoreResumeDecisionTable.Decision {
        RuntimeRestoreResumeDecisionTable.decide(
            signal,
            on: RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: session.stored.projection,
                lease: session.lease,
                claimState: restorationClaimState(
                    session.stored.restorationClaim,
                    now: restorationClock.now(),
                ),
            ),
        )
    }

    internal func restorationClaimState(
        _ claim: RuntimeRestorationClaim?,
        now: Date,
    ) -> RuntimeRestoreResumeDecisionTable.ClaimState {
        guard let claim else { return .absent }
        guard claim.expiresAt > now else { return .expired }
        return claim.ownerToken == restorationOwnerToken ? .ownedLive : .foreignLive
    }

    private func reconcileRestoreClaimConflict(
        at host: ExternalAgentSessionReference,
    ) async throws -> RuntimeRestoreResult {
        try await withPersistedState { plane, loaded in
            guard let loaded else { return .stale }
            plane.sessions = plane.reconciledRegistry(
                candidate: plane.sessions,
                persisted: loaded,
            )
            guard let persisted = plane.sessions[host] else { return .stale }
            switch plane.restoreDecision(.persistConflict, for: persisted) {
            case .adoptPersisted, .stale:
                return .stale
            case let .throwHost(error):
                throw error
            case .acquireClaim, .beginResume, .renewClaim, .restoreClaim:
                throw RuntimeHostError.invalidEvent
            }
        }
    }

    internal func makeRestorationClaim() -> RuntimeRestorationClaim {
        RuntimeRestorationClaim(
            ownerToken: restorationOwnerToken,
            expiresAt: restorationClock.now().addingTimeInterval(60),
        )
    }

    private func requireSameIdentityResumeOrRelease(
        _ original: Session,
        at host: ExternalAgentSessionReference,
    ) async throws {
        do {
            try require(.sameIdentityResume, in: original.stored.capabilitySnapshot)
        } catch {
            _ = try await releaseStaleRestoreReservation(original, at: host)
            throw error
        }
    }

    private func releaseStaleRestoreReservation(
        _ original: Session,
        at host: ExternalAgentSessionReference,
    ) async throws -> RuntimeRestoreResult {
        try await commit(host: host) { plane, registry in
            guard plane.sessionUnchanged(original, at: host, in: registry),
                  var current = registry[host],
                  !current.stored.projection.isTerminal
            else { return .stale }
            current.stored = current.stored.withProjection(.interrupted)
            current.lease = .none
            current.revision += 1
            registry[host] = current
            return .stale
        }
    }

    internal func sessionUnchanged(
        _ original: Session?,
        at host: ExternalAgentSessionReference,
        in registry: SessionRegistry? = nil,
    ) -> Bool {
        let current = registry?[host] ?? sessions[host]
        guard current?.lease.isActive != true else { return false }
        return current == original
    }

    internal func activeAdapter(
        for hostReference: ExternalAgentSessionReference,
    ) throws -> (any ExternalAgentRuntimeAdapter, RuntimeStoredSession) {
        guard let session = sessions[hostReference],
              session.lease.isActive,
              !session.stored.projection.isTerminal
        else {
            throw RuntimeHostError.invalidEvent
        }
        guard let adapter = adapters[session.stored.adapterID] else {
            throw RuntimeHostError.adapterNotFound(session.stored.adapterID)
        }
        return (adapter, session.stored)
    }

    internal func beginOperation(
        for hostReference: ExternalAgentSessionReference,
        requiring capability: RuntimeCapability,
    ) throws -> OperationClaim {
        guard pendingPersistenceMutations[hostReference, default: 0] == 0 else {
            throw RuntimeHostError.invalidEvent
        }
        let binding = try activeAdapter(for: hostReference)
        try require(capability, in: binding.1.capabilitySnapshot)
        guard let current = sessions[hostReference] else { throw RuntimeHostError.invalidEvent }
        return OperationClaim(
            adapter: binding.0,
            session: binding.1,
            lease: current.lease,
        )
    }

    internal func validateOperationClaim(
        _ claim: OperationClaim,
        at hostReference: ExternalAgentSessionReference,
    ) throws {
        guard pendingPersistenceMutations[hostReference, default: 0] == 0,
              let current = sessions[hostReference],
              current.lease == claim.lease,
              current.stored.runReference == claim.session.runReference,
              !current.stored.projection.isTerminal
        else { throw RuntimeHostError.invalidEvent }
    }

    internal func require(_ capability: RuntimeCapability, in capabilities: RuntimeCapabilities) throws {
        switch capabilities[capability] {
        case .supported:
            return
        case .unknown:
            throw RuntimeHostError.capabilityUnknown(capability)
        case .unsupported:
            throw RuntimeHostError.capabilityUnsupported(capability)
        }
    }
}

struct OperationClaim {
    let adapter: any ExternalAgentRuntimeAdapter
    let session: RuntimeStoredSession
    let lease: RuntimeControlPlane.RuntimeLease
}

extension RuntimeProjection {
    var isTerminal: Bool {
        switch self {
        case .launchBlocked, .launchCancelled, .launchFailed, .completed, .failed, .interrupted:
            true
        case .policyPending, .policyReady, .launching, .running, .eventProjected,
             .eventDuplicateIgnored, .eventOutOfOrder:
            false
        }
    }
}

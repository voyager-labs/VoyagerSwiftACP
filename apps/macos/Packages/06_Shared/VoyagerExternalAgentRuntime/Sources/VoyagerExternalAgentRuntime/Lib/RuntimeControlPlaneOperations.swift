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
            try await claim.adapter.respondToApproval(RuntimeApprovalRequest(
                externalAgentSessionReference: hostReference,
                providerInternalSessionReference: providerReference,
                requestID: requestID,
                operationID: operationID,
                runReference: session.runReference,
                authorizationGeneration: session.contextPolicy.authorizationGeneration,
            ))
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
            try await claim.adapter.enqueueInput(RuntimeQueuedInputRequest(
                operationID: operationID,
                runReference: claim.session.runReference,
                input: input,
            ))
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
            try await claim.adapter.requestCancellation(RuntimeCancellationRequest(
                operationID: operationID,
                runReference: claim.session.runReference,
            ))
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
        if let claim = stored.restorationClaim,
           claim.ownerToken != restorationOwnerToken,
           claim.isLive(at: Date())
        {
            return .stale
        }
        guard let providerInternalSessionReference = stored.providerInternalSessionReference,
              stored.contextPolicy.hasSameExecutionContext(as: expectedContext),
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
            compatibility = try await adapter.restartCompatibility(for: binding)
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

    private func acquireRestoreClaim(
        _ original: Session,
        at host: ExternalAgentSessionReference,
    ) async throws -> RuntimeRestoreResult {
        guard store is any RuntimeStateStoreHostMutation else {
            return try await mutateAfterPersistedTransitions { plane in
                try Task.checkCancellation()
                guard plane.sessionUnchanged(original, at: host),
                      var current = plane.sessions[host]
                else { return .stale }
                _ = current.issueLease(RuntimeLease.restored)
                plane.sessions[host] = current
                return .restored
            }
        }
        do {
            return try await commit(host: host) { plane, registry in
                guard plane.sessionUnchanged(original, at: host, in: registry),
                      var current = registry[host],
                      plane.canAcquireRestorationClaim(current.stored.restorationClaim)
                else { return .stale }
                current.stored = current.stored.withRestorationClaim(plane.makeRestorationClaim())
                _ = current.issueLease(RuntimeLease.restored)
                registry[host] = current
                return .restored
            }
        } catch RuntimeHostError.persistenceFailure {
            return .stale
        }
    }

    private func canAcquireRestorationClaim(_ claim: RuntimeRestorationClaim?) -> Bool {
        claim.map { $0.ownerToken == restorationOwnerToken || !$0.isLive(at: Date()) } ?? true
    }

    internal func makeRestorationClaim() -> RuntimeRestorationClaim {
        RuntimeRestorationClaim(
            ownerToken: restorationOwnerToken,
            expiresAt: Date().addingTimeInterval(60),
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

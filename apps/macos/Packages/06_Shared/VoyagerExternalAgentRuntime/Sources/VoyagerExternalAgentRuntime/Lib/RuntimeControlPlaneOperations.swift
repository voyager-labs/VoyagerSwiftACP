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
        let (adapter, session) = try beginOperation(for: hostReference, requiring: .approval)
        do {
            guard let providerReference = session.providerInternalSessionReference
            else { throw RuntimeHostError.malformedAdapterResponse }
            try await adapter.respondToApproval(RuntimeApprovalRequest(
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
    }

    func enqueueInput(
        hostReference: ExternalAgentSessionReference,
        operationID: RuntimeOperationID,
        input: RuntimeSensitiveInput,
    ) async throws {
        guard operationID.isWithinRuntimeBounds,
              input.rawValue.unicodeScalars.count <= RuntimeBoundaryLimits.sensitiveInputScalars
        else { throw RuntimeHostError.malformedAdapterResponse }
        let (adapter, session) = try beginOperation(for: hostReference, requiring: .queuedInput)
        do {
            try await adapter.enqueueInput(RuntimeQueuedInputRequest(
                operationID: operationID,
                runReference: session.runReference,
                input: input,
            ))
        } catch {
            throw normalizeAdapterError(error)
        }
    }

    func requestCancellation(
        hostReference: ExternalAgentSessionReference,
        operationID: RuntimeOperationID,
    ) async throws {
        guard operationID.isWithinRuntimeBounds else { throw RuntimeHostError.malformedAdapterResponse }
        let (adapter, session) = try beginOperation(for: hostReference, requiring: .cancellation)
        do {
            try await adapter.requestCancellation(RuntimeCancellationRequest(
                operationID: operationID,
                runReference: session.runReference,
            ))
        } catch {
            throw normalizeAdapterError(error)
        }
    }

    func restore(
        hostReference: ExternalAgentSessionReference,
        expectedContext: RuntimeContextPolicy,
    ) async throws -> RuntimeRestoreResult {
        try await hydrateIfNeeded()
        guard let original = sessions[hostReference] else { return .stale }
        guard !original.active else { throw RuntimeHostError.activeRunExists }
        let stored = original.stored
        guard !stored.projection.isTerminal else { return .stale }
        guard let providerInternalSessionReference = stored.providerInternalSessionReference,
              stored.contextPolicy.hasSameExecutionContext(as: expectedContext),
              let adapter = adapters[stored.adapterID],
              stored.providerNamespace == adapter.descriptor.providerNamespace,
              stored.adapterVersion == adapter.descriptor.adapterVersion,
              stored.providerBranch == adapter.descriptor.providerBranch,
              stored.capabilitySnapshot == adapter.descriptor.capabilities
        else { return try await releaseStaleRestoreReservation(original, at: hostReference) }
        try require(.sameIdentityResume, in: stored.capabilitySnapshot)
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
            return try await mutateAfterPersistedTransitions { plane in
                guard plane.sessionUnchanged(original, at: hostReference) else { return .stale }
                plane.sessions[hostReference] = Session(
                    stored: stored,
                    active: true,
                    awaitingResumption: true,
                )
                return .restored
            }
        case .stale, .incompatible:
            return try await releaseStaleRestoreReservation(original, at: hostReference)
        }
    }

    private func releaseStaleRestoreReservation(
        _ original: Session,
        at host: ExternalAgentSessionReference,
    ) async throws -> RuntimeRestoreResult {
        try await commit(host: host) { plane in
            guard plane.sessionUnchanged(original, at: host),
                  var current = plane.sessions[host],
                  !current.stored.projection.isTerminal
            else { return .stale }
            current.stored = current.stored.withProjection(.interrupted)
            current.active = false
            current.awaitingResumption = false
            plane.sessions[host] = current
            return .stale
        }
    }

    private func sessionUnchanged(_ original: Session?, at host: ExternalAgentSessionReference) -> Bool {
        guard sessions[host]?.active != true else { return false }
        return sessions[host]?.stored == original?.stored
    }

    internal func activeAdapter(
        for hostReference: ExternalAgentSessionReference,
    ) throws -> (any ExternalAgentRuntimeAdapter, RuntimeStoredSession) {
        guard let session = sessions[hostReference], session.active else {
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
    ) throws -> (any ExternalAgentRuntimeAdapter, RuntimeStoredSession) {
        guard terminalPending[hostReference, default: 0] == 0 else { throw RuntimeHostError.invalidEvent }
        guard !persistingHosts.contains(hostReference) else { throw RuntimeHostError.invalidEvent }
        let binding = try activeAdapter(for: hostReference)
        try require(capability, in: binding.1.capabilitySnapshot)
        return binding
    }

    internal func beginTerminalTransition(_ hostReference: ExternalAgentSessionReference) {
        terminalPending[hostReference, default: 0] += 1
    }

    internal func endTerminalTransition(_ hostReference: ExternalAgentSessionReference) {
        let remaining = terminalPending[hostReference, default: 0] - 1
        if remaining <= 0 {
            terminalPending[hostReference] = nil
        } else {
            terminalPending[hostReference] = remaining
        }
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

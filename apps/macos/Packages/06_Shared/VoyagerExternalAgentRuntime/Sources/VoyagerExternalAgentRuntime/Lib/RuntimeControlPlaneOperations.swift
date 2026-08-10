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
            finishOperation(for: hostReference)
        } catch {
            finishOperation(for: hostReference)
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
            finishOperation(for: hostReference)
        } catch {
            finishOperation(for: hostReference)
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
            finishOperation(for: hostReference)
        } catch {
            finishOperation(for: hostReference)
            throw normalizeAdapterError(error)
        }
    }

    func restore(
        hostReference: ExternalAgentSessionReference,
        expectedContext: RuntimeContextPolicy,
    ) async throws -> RuntimeRestoreResult {
        try await hydrateIfNeeded()
        let original = sessions[hostReference]
        guard original?.active != true else { throw RuntimeHostError.activeRunExists }
        guard sessionUnchanged(original, at: hostReference),
              let stored = original?.stored,
              !stored.projection.isTerminal,
              let providerInternalSessionReference = stored.providerInternalSessionReference,
              stored.contextPolicy.hasSameExecutionContext(as: expectedContext),
              let adapter = adapters[stored.adapterID],
              stored.providerNamespace == adapter.descriptor.providerNamespace,
              stored.adapterVersion == adapter.descriptor.adapterVersion,
              stored.providerBranch == adapter.descriptor.providerBranch,
              stored.capabilitySnapshot == adapter.descriptor.capabilities
        else { return .stale }
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
            contextPolicy: stored.contextPolicy,
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
        guard !terminalPending.contains(hostReference) else { throw RuntimeHostError.invalidEvent }
        guard !persistingHosts.contains(hostReference) else { throw RuntimeHostError.invalidEvent }
        let binding = try activeAdapter(for: hostReference)
        try require(capability, in: binding.1.capabilitySnapshot)
        inFlightOperations[hostReference, default: 0] += 1
        return binding
    }

    internal func finishOperation(for hostReference: ExternalAgentSessionReference) {
        let remaining = max(0, inFlightOperations[hostReference, default: 0] - 1)
        if remaining == 0 {
            inFlightOperations[hostReference] = nil
            operationWaiters.removeValue(forKey: hostReference)?.forEach { $0.resume() }
        } else {
            inFlightOperations[hostReference] = remaining
        }
    }

    internal func waitForOperationsBeforeTerminal(_ hostReference: ExternalAgentSessionReference) async {
        terminalPending.insert(hostReference)
        guard inFlightOperations[hostReference, default: 0] > 0 else { return }
        await withCheckedContinuation { continuation in
            operationWaiters[hostReference, default: []].append(continuation)
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

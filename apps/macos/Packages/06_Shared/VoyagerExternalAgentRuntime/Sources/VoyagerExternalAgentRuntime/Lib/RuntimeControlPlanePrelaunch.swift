import Foundation

public extension RuntimeControlPlane {
    func projectPrelaunch(
        _ request: RuntimeLaunchRequest,
        as projection: RuntimePrelaunchProjection,
    ) async throws {
        try await hydrateIfNeeded()
        try await synchronizePersistedTerminalBeforeReplacement(request)
        try await commit(host: request.externalAgentSessionReference) { plane, registry in
            try plane.validateBoundary(request)
            guard let adapter = plane.adapters[request.adapterID] else {
                throw RuntimeHostError.adapterNotFound(request.adapterID)
            }
            let host = request.externalAgentSessionReference
            try plane.requireAvailableRunReference(request.runReference, excluding: host, in: registry)
            let previousRevision = registry[host]?.revision ?? 0
            if let current = registry[host] {
                try plane.validatePrelaunchTransition(
                    current,
                    request: request,
                    projection: projection,
                    descriptor: adapter.descriptor,
                )
            } else {
                guard registry.count < RuntimeBoundaryLimits.persistedSessions else {
                    throw RuntimeHostError.malformedAdapterResponse
                }
            }
            let descriptor = adapter.descriptor
            if var current = registry[host], current.stored.runReference == request.runReference {
                current.stored = current.stored.withProjection(projection.projection)
                current.revision += 1
                registry[host] = current
                return
            }
            registry[host] = Session(stored: RuntimeStoredSession(
                externalAgentSessionReference: host,
                providerInternalSessionReference: nil,
                runReference: request.runReference,
                adapterID: descriptor.id,
                adapterVersion: descriptor.adapterVersion,
                capabilitySnapshot: descriptor.capabilities,
                storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
                projection: projection.projection,
                providerLaunchAttempted: false,
                lastSequence: 0,
                acceptedEventCount: 0,
                processedEventCount: 0,
                acceptedIdempotencyKeys: [],
                providerNamespace: descriptor.providerNamespace,
                providerBranch: descriptor.providerBranch,
            ), revision: previousRevision + 1)
        }
    }
}

private extension RuntimeControlPlane {
    func synchronizePersistedTerminalBeforeReplacement(
        _ request: RuntimeLaunchRequest,
    ) async throws {
        let host = request.externalAgentSessionReference
        guard let current = sessions[host] else { return }
        // 소유자 작업이 사라진 분리 소유자는 스스로 수렴하지 못하므로 교체 전 저장된 terminal 채택을 허용한다.
        let ownershipReleased = !current.lease.isActive || current.lease.isDetachedOwner
        guard ownershipReleased,
              !current.stored.projection.isTerminal,
              current.stored.runReference != request.runReference
        else { return }
        try await withPersistedState { plane, loaded in
            guard plane.sessions[host] == current,
                  var adopted = plane.adoptingPersistedTerminal(
                      host: host,
                      runReference: current.stored.runReference,
                      expectedSession: current,
                      loaded: loaded,
                  )
            else { return }
            // 같은 평면 terminal 경계와 동일하게 분리 소유권은 채택과 함께 해제한다.
            if adopted.lease.isDetachedOwner {
                adopted.lease = .none
            }
            plane.sessions[host] = adopted
        }
        try Task.checkCancellation()
    }

    func validatePrelaunchTransition(
        _ current: Session,
        request: RuntimeLaunchRequest,
        projection: RuntimePrelaunchProjection,
        descriptor: RuntimeAdapterDescriptor,
    ) throws {
        guard !current.lease.isActive else { throw RuntimeHostError.activeRunExists }
        let sameRun = current.stored.runReference == request.runReference
        let recoverablePreProviderLaunch = current.stored.projection == .launching
            && current.stored.providerInternalSessionReference == nil
            && current.stored.providerLaunchAttempted == false
        let mayAdvancePrelaunch = sameRun
            && ([.policyPending, .policyReady].contains(current.stored.projection)
                || recoverablePreProviderLaunch)
        if sameRun, current.stored.projection.isTerminal {
            throw RuntimeHostError.duplicateRunReference
        }
        if sameRun,
           current.stored.projection == .launching,
           current.stored.providerLaunchAttempted != false
        {
            throw RuntimeHostError.duplicateRunReference
        }
        if sameRun,
           [.policyPending, .policyReady].contains(current.stored.projection),
           !RuntimeFreshRunDecisionTable.allowsPrelaunchTransition(
               from: current.stored.projection,
               to: projection.projection,
           )
        {
            throw RuntimeHostError.invalidEvent
        }
        if !current.stored.projection.isTerminal, !mayAdvancePrelaunch {
            throw RuntimeHostError.activeRunExists
        }
        guard !mayAdvancePrelaunch
            || current.stored.matchesLaunchSnapshot(request, descriptor: descriptor)
        else { throw RuntimeHostError.invalidEvent }
    }
}

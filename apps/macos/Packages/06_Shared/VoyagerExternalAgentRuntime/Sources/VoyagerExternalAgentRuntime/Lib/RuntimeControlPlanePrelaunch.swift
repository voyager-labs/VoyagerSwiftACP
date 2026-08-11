import Foundation

public extension RuntimeControlPlane {
    func projectPrelaunch(
        _ request: RuntimeLaunchRequest,
        as projection: RuntimePrelaunchProjection,
    ) async throws {
        try await hydrateIfNeeded()
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
                contextPolicy: request.contextPolicy,
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
    func validatePrelaunchTransition(
        _ current: Session,
        request: RuntimeLaunchRequest,
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
        if !current.stored.projection.isTerminal, !mayAdvancePrelaunch {
            throw RuntimeHostError.activeRunExists
        }
        guard !mayAdvancePrelaunch
            || current.stored.matchesLaunchSnapshot(request, descriptor: descriptor)
        else { throw RuntimeHostError.invalidEvent }
    }
}

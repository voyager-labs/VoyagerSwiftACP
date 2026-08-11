import Foundation

public extension RuntimeControlPlane {
    func projectPrelaunch(
        _ request: RuntimeLaunchRequest,
        as projection: RuntimePrelaunchProjection,
    ) async throws {
        try await hydrateIfNeeded()
        try await commit(host: request.externalAgentSessionReference) { plane in
            try plane.validateBoundary(request)
            guard let adapter = plane.adapters[request.adapterID] else {
                throw RuntimeHostError.adapterNotFound(request.adapterID)
            }
            let host = request.externalAgentSessionReference
            try plane.requireAvailableRunReference(request.runReference, excluding: host)
            if let current = plane.sessions[host] {
                guard !current.active else { throw RuntimeHostError.activeRunExists }
                let sameRun = current.stored.runReference == request.runReference
                let recoverablePreProviderLaunch = current.stored.projection == .launching
                    && current.stored.providerInternalSessionReference == nil
                let mayAdvancePrelaunch = sameRun
                    && ([.policyPending, .policyReady].contains(current.stored.projection)
                        || recoverablePreProviderLaunch)
                if !current.stored.projection.isTerminal, !mayAdvancePrelaunch {
                    throw RuntimeHostError.activeRunExists
                }
                if sameRun, current.stored.projection.isTerminal {
                    throw RuntimeHostError.duplicateRunReference
                }
                guard !mayAdvancePrelaunch
                    || current.stored.matchesLaunchSnapshot(request, descriptor: adapter.descriptor)
                else { throw RuntimeHostError.invalidEvent }
            } else {
                guard plane.sessions.count < RuntimeBoundaryLimits.persistedSessions else {
                    throw RuntimeHostError.malformedAdapterResponse
                }
            }
            let descriptor = adapter.descriptor
            plane.sessions[host] = Session(stored: RuntimeStoredSession(
                externalAgentSessionReference: host,
                providerInternalSessionReference: nil,
                runReference: request.runReference,
                adapterID: descriptor.id,
                adapterVersion: descriptor.adapterVersion,
                capabilitySnapshot: descriptor.capabilities,
                contextPolicy: request.contextPolicy,
                projection: projection.projection,
                lastSequence: 0,
                acceptedEventCount: 0,
                processedEventCount: 0,
                acceptedIdempotencyKeys: [],
                providerNamespace: descriptor.providerNamespace,
                providerBranch: descriptor.providerBranch,
            ))
        }
    }
}

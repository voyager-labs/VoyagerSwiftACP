import Foundation

public extension RuntimeControlPlane {
    func retireTerminalSession(
        hostReference: ExternalAgentSessionReference,
    ) async throws {
        try await hydrateIfNeeded()
        guard let current = sessions[hostReference] else {
            clearRetiredSessionMetadata(for: hostReference)
            return
        }
        guard current.stored.projection.isTerminal,
              !current.lease.isActive
        else { throw RuntimeHostError.invalidEvent }

        do {
            try await commit(host: hostReference) { _, registry in
                guard registry[hostReference] == current else {
                    throw RuntimeHostError.persistenceConflict
                }
                registry.removeValue(forKey: hostReference)
            }
        } catch RuntimeHostError.persistenceConflict {
            try await reconcileTerminalRetirementConflict(at: hostReference)
            return
        }
        clearRetiredSessionMetadata(for: hostReference)
    }
}

private extension RuntimeControlPlane {
    func reconcileTerminalRetirementConflict(
        at host: ExternalAgentSessionReference,
    ) async throws {
        try await withPersistedState { plane, loaded in
            if let loaded {
                plane.sessions = plane.reconciledRegistry(
                    candidate: plane.sessions,
                    persisted: loaded,
                )
            } else {
                plane.sessions[host] = nil
            }
            guard loaded?.sessions.contains(where: {
                $0.externalAgentSessionReference == host
            }) != true else {
                throw RuntimeHostError.persistenceConflict
            }
            plane.clearRetiredSessionMetadata(for: host)
        }
    }

    func clearRetiredSessionMetadata(
        for host: ExternalAgentSessionReference,
    ) {
        cleanupFailureEvidenceByHost[host] = nil
        activeRestoredResumeAttempts[host] = nil
    }
}

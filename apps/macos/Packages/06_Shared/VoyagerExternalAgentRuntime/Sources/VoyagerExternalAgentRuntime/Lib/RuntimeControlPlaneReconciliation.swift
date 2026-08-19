import Foundation

extension RuntimeControlPlane {
    func reconciledRegistry(
        candidate: SessionRegistry,
        persisted: RuntimeStoredState,
    ) -> SessionRegistry {
        Dictionary(uniqueKeysWithValues: persisted.sessions.map { stored in
            let host = stored.externalAgentSessionReference
            if let preferred = candidate[host], preferred.stored == stored {
                return (host, preferred)
            }
            return (host, Session(stored: stored))
        })
    }

    func terminalResult(for stored: RuntimeStoredSession) -> RuntimeResult? {
        guard let outcome = outcome(for: stored.projection) else { return nil }
        return RuntimeResult(runReference: stored.runReference, outcome: outcome, artifactReferences: [])
    }

    func adoptingPersistedTerminal(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        expectedSession: Session?,
        loaded: RuntimeStoredState?,
    ) -> Session? {
        guard let stored = loaded?.sessions.first(where: {
            $0.externalAgentSessionReference == host && $0.runReference == runReference
        }), terminalResult(for: stored) != nil else {
            return nil
        }
        guard let expectedSession else { return Session(stored: stored) }
        return Session(
            stored: stored,
            lease: expectedSession.lease,
            revision: expectedSession.revision,
        )
    }
}

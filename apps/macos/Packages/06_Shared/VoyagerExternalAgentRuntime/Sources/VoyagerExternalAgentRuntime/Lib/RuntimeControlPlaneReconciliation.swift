import Foundation

extension RuntimeControlPlane {
    func reconciledRegistry(
        candidate: SessionRegistry,
        persisted: RuntimeStoredState,
    ) -> SessionRegistry {
        Dictionary(uniqueKeysWithValues: persisted.sessions.map { stored in
            let host = stored.externalAgentSessionReference
            guard let preferred = candidate[host] else {
                return (host, Session(stored: stored))
            }
            if preferred.stored == stored {
                return (host, preferred)
            }
            // 같은 run의 live 소유자(launching/consuming)는 저장 스냅샷이 바뀌어도
            // in-memory lease/revision을 보존한다. restored/resuming은 persisted claim이
            // 이 평면의 live 소유일 때만 보존한다. claim 데이터는 새 stored 스냅샷이 항상
            // 권위를 가지므로 stale 소유 claim이 되살아나지 않는다. detached/none 소유자와
            // 다른 run 스냅샷은 초기화한다.
            if preferred.stored.runReference == stored.runReference {
                switch preferred.lease {
                case .launching, .consuming:
                    return (host, Session(stored: stored, lease: preferred.lease, revision: preferred.revision))
                case .restored, .resuming:
                    if let claim = stored.restorationClaim,
                       claim.ownerToken == restorationOwnerToken,
                       claim.expiresAt > restorationClock.now()
                    {
                        return (host, Session(stored: stored, lease: preferred.lease, revision: preferred.revision))
                    }
                    return (host, Session(stored: stored))
                case .none, .detachedLaunching, .detachedConsuming:
                    return (host, Session(stored: stored))
                }
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

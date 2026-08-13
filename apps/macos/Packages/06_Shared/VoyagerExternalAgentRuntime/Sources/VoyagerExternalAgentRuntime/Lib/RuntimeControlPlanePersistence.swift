import Foundation

extension RuntimeControlPlane {
    func commit<T: Sendable>(
        host: ExternalAgentSessionReference,
        _ mutation: @Sendable (
            isolated RuntimeControlPlane,
            inout SessionRegistry,
        ) throws -> T,
    ) async throws -> T {
        guard host.rawValue.isRuntimeBounded else { throw RuntimeHostError.malformedAdapterResponse }
        pendingPersistenceMutations[host, default: 0] += 1
        defer { finishPendingPersistenceMutation(host) }
        try await acquirePersistenceMutation()
        do {
            try Task.checkCancellation()
            var candidate = sessions
            let result = try mutation(self, &candidate)
            let state = RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: candidate.values.map(\.stored).sorted {
                    $0.externalAgentSessionReference.rawValue < $1.externalAgentSessionReference.rawValue
                },
            )
            do {
                if let store = store as? any RuntimeStateStoreHostMutation {
                    let committed = try await store.updateHost(
                        host,
                        expected: sessions[host]?.stored,
                        replacement: candidate[host]?.stored,
                    )
                    sessions = reconciledRegistry(from: committed, preferring: candidate)
                } else {
                    try await store.save(state)
                    sessions = candidate
                }
            } catch {
                throw RuntimeHostError.persistenceFailure
            }
            releasePersistenceMutation()
            return result
        } catch {
            releasePersistenceMutation()
            throw error
        }
    }

    func mutateAfterPersistedTransitions<T: Sendable>(
        _ mutation: @Sendable (isolated RuntimeControlPlane) throws -> T,
    ) async throws -> T {
        try await acquirePersistenceMutation()
        defer { releasePersistenceMutation() }
        return try mutation(self)
    }

    func loadPersistedTerminalResult(
        host: ExternalAgentSessionReference,
        runReference: RuntimeRunReference,
        expectedSession: Session? = nil,
    ) async throws -> RuntimeResult? {
        try await acquirePersistenceMutation()
        defer { releasePersistenceMutation() }
        try Task.checkCancellation()
        let state: RuntimeStoredState?
        do {
            state = try await store.load()?.validatedForRuntime()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
        if let expectedSession, sessions[host] != expectedSession {
            try Task.checkCancellation()
            return nil
        }
        guard let stored = state?.sessions.first(where: {
            $0.externalAgentSessionReference == host && $0.runReference == runReference
        }), outcome(for: stored.projection) != nil
        else {
            try Task.checkCancellation()
            return nil
        }
        if let current = sessions[host] {
            sessions[host] = Session(
                stored: stored,
                lease: current.lease,
                revision: current.revision,
            )
        } else {
            sessions[host] = Session(stored: stored)
        }
        try Task.checkCancellation()
        return storedTerminalResult(host: host, runReference: runReference)
    }

    private func acquirePersistenceMutation() async throws {
        guard persistenceMutationLocked else {
            persistenceMutationLocked = true
            return
        }
        guard persistenceMutationWaiters.count < RuntimeBoundaryLimits.persistenceMutationWaiters else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        await withCheckedContinuation { continuation in
            persistenceMutationWaiters.append(continuation)
        }
    }

    private func releasePersistenceMutation() {
        guard !persistenceMutationWaiters.isEmpty else {
            persistenceMutationLocked = false
            return
        }
        persistenceMutationWaiters.removeFirst().resume()
    }

    private func finishPendingPersistenceMutation(_ host: ExternalAgentSessionReference) {
        let remaining = pendingPersistenceMutations[host, default: 0] - 1
        pendingPersistenceMutations[host] = remaining > 0 ? remaining : nil
    }

    private func reconciledRegistry(
        from state: RuntimeStoredState,
        preferring candidate: SessionRegistry,
    ) -> SessionRegistry {
        Dictionary(uniqueKeysWithValues: state.sessions.map { stored in
            let host = stored.externalAgentSessionReference
            if let preferred = candidate[host], preferred.stored.hasSamePersistedState(as: stored) {
                return (host, preferred)
            }
            return (host, Session(stored: stored))
        })
    }
}

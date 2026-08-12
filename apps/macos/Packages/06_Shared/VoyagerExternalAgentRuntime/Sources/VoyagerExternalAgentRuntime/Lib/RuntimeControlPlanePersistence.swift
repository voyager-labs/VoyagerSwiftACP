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
                try await store.save(state)
            } catch {
                throw RuntimeHostError.persistenceFailure
            }
            sessions = candidate
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
}

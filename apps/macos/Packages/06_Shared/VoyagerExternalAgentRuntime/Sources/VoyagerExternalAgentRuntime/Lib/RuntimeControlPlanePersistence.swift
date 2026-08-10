import Foundation

extension RuntimeControlPlane {
    func commit<T: Sendable>(
        host: ExternalAgentSessionReference,
        _ mutation: @Sendable (isolated RuntimeControlPlane) throws -> T,
    ) async throws -> T {
        await acquirePersistenceMutation()
        persistingHosts.insert(host)
        let previous = sessions
        do {
            let result = try mutation(self)
            let state = RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: sessions.values.map(\.stored).sorted {
                    $0.externalAgentSessionReference.rawValue < $1.externalAgentSessionReference.rawValue
                },
            )
            do {
                try await store.save(state)
            } catch {
                throw RuntimeHostError.persistenceFailure
            }
            releasePersistenceMutation()
            return result
        } catch {
            sessions = previous
            releasePersistenceMutation()
            throw error
        }
    }

    func mutateAfterPersistedTransitions<T: Sendable>(
        _ mutation: @Sendable (isolated RuntimeControlPlane) throws -> T,
    ) async throws -> T {
        await acquirePersistenceMutation()
        defer { releasePersistenceMutation() }
        return try mutation(self)
    }

    private func acquirePersistenceMutation() async {
        guard persistenceMutationLocked else {
            persistenceMutationLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            persistenceMutationWaiters.append(continuation)
        }
    }

    private func releasePersistenceMutation() {
        persistingHosts.removeAll()
        guard !persistenceMutationWaiters.isEmpty else {
            persistenceMutationLocked = false
            return
        }
        persistenceMutationWaiters.removeFirst().resume()
    }
}

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
            do {
                let outcome = try await store.apply(RuntimeStateMutation(
                    host: host,
                    expected: sessions[host]?.stored,
                    replacement: candidate[host]?.stored,
                ))
                switch outcome {
                case let .committed(committed):
                    let validated = try validatedPersistedState(committed)
                    sessions = reconciledRegistry(candidate: candidate, persisted: validated)
                case .conflict:
                    throw RuntimeHostError.persistenceConflict
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as RuntimeStateStoreError {
                throw mapStoreError(error)
            } catch {
                throw error
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

    func withPersistedState<T: Sendable>(
        _ body: @Sendable (isolated RuntimeControlPlane, RuntimeStoredState?) throws -> T,
    ) async throws -> T {
        try await acquirePersistenceMutation()
        defer { releasePersistenceMutation() }
        try Task.checkCancellation()
        let state: RuntimeStoredState?
        do {
            if let loaded = try await store.load() {
                state = try validatedPersistedState(loaded)
            } else {
                state = nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RuntimeStateStoreError {
            throw mapStoreError(error)
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
        return try body(self, state)
    }

    func mapStoreError(_ error: RuntimeStateStoreError) -> RuntimeHostError {
        switch error {
        case .invalidSnapshot:
            .invalidPersistedState
        case .unavailable:
            .persistenceFailure
        case let .unsupportedSchemaVersion(version):
            .unsupportedSchemaVersion(version)
        }
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

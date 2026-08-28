import Foundation

/// persistence mutation 대기 핸들. resume-once 계약으로 이중 재개를 방지한다.
/// actor 직렬화와 nil-out 재개로 단일 접근이 보장되므로 @unchecked Sendable이다.
final class PersistenceMutationWaiterHandle: @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resumeGranted(_ granted: Bool) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: granted)
        }
    }
}

/// 취소 핸들러가 등록된 waiter를 회수하기 위한 홀더.
final class PersistenceMutationWaiterHandleHolder: @unchecked Sendable {
    private var handle: PersistenceMutationWaiterHandle?

    func set(_ handle: PersistenceMutationWaiterHandle) {
        self.handle = handle
    }

    func take() -> PersistenceMutationWaiterHandle? {
        let current = handle
        handle = nil
        return current
    }
}

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
        let granted = try await acquirePersistenceMutation()
        guard granted else { throw CancellationError() }
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
        let granted = try await acquirePersistenceMutation()
        guard granted else { throw CancellationError() }
        defer { releasePersistenceMutation() }
        return try mutation(self)
    }

    func withPersistedState<T: Sendable>(
        _ body: @Sendable (isolated RuntimeControlPlane, RuntimeStoredState?) throws -> T,
    ) async throws -> T {
        let granted = try await acquirePersistenceMutation()
        guard granted else { throw CancellationError() }
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

    private func acquirePersistenceMutation() async throws -> Bool {
        guard persistenceMutationLocked else {
            persistenceMutationLocked = true
            return true
        }
        guard persistenceMutationWaiters.count < RuntimeBoundaryLimits.persistenceMutationWaiters else {
            throw RuntimeHostError.malformedAdapterResponse
        }
        let holder = PersistenceMutationWaiterHandleHolder()
        return await withTaskCancellationHandler(operation: {
            await suspendPersistenceMutationWaiter(holder: holder)
        }, onCancel: {
            Task { await self.cancelPersistenceMutationWaiter(holder) }
        })
    }

    private func suspendPersistenceMutationWaiter(
        holder: PersistenceMutationWaiterHandleHolder,
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            // 등록 전 취소는 대기열에 넣지 않고 즉시 탈출시킨다(cancel-before-register 경합).
            if Task.isCancelled {
                continuation.resume(returning: false)
                return
            }
            let handle = PersistenceMutationWaiterHandle(continuation)
            holder.set(handle)
            persistenceMutationWaiters.append(handle)
        }
    }

    private func cancelPersistenceMutationWaiter(_ holder: PersistenceMutationWaiterHandleHolder) {
        guard let handle = holder.take() else { return }
        // 이미 grant로 소비됐으면 identity 검색이 실패하고 resume-once가 no-op으로 처리한다.
        if let index = persistenceMutationWaiters.firstIndex(where: { $0 === handle }) {
            persistenceMutationWaiters.remove(at: index)
        }
        handle.resumeGranted(false)
    }

    private func releasePersistenceMutation() {
        guard !persistenceMutationWaiters.isEmpty else {
            persistenceMutationLocked = false
            return
        }
        persistenceMutationWaiters.removeFirst().resumeGranted(true)
    }

    private func finishPendingPersistenceMutation(_ host: ExternalAgentSessionReference) {
        let remaining = pendingPersistenceMutations[host, default: 0] - 1
        pendingPersistenceMutations[host] = remaining > 0 ? remaining : nil
    }
}

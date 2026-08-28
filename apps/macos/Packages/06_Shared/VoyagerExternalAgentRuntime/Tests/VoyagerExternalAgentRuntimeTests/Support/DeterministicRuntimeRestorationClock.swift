import Foundation
import os.lock
@testable import VoyagerExternalAgentRuntime

struct DeterministicRuntimeRestorationClock {
    private let dateState: OSAllocatedUnfairLock<Date>
    private let sleeper: DeterministicRuntimeRestorationSleeper

    init(currentDate: Date) {
        dateState = OSAllocatedUnfairLock(initialState: currentDate)
        sleeper = DeterministicRuntimeRestorationSleeper()
    }

    var currentDate: Date {
        dateState.withLock { $0 }
    }

    var runtimeClock: RuntimeRestorationClock {
        RuntimeRestorationClock(
            now: { dateState.withLock { $0 } },
            sleep: { _ in try await sleeper.sleep() },
        )
    }

    func advanced(by interval: TimeInterval) -> Self {
        Self(currentDate: currentDate.addingTimeInterval(interval))
    }

    func advance(by interval: TimeInterval) {
        dateState.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    func releaseSleepers() async {
        await sleeper.releaseAll()
    }

    func waitUntilSleeping() async {
        await sleeper.waitUntilSleeping()
    }

    func isSleeping() async -> Bool {
        await sleeper.isSleeping()
    }
}

func runtimeRestoreClaimState(
    _ claim: RuntimeRestorationClaim?,
    ownerToken: String,
    now: Date,
) -> RuntimeRestoreResumeDecisionTable.ClaimState {
    guard let claim else { return .absent }
    guard claim.expiresAt > now else { return .expired }
    return claim.ownerToken == ownerToken ? .ownedLive : .foreignLive
}

private actor DeterministicRuntimeRestorationSleeper {
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var waiterCountWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
                let ready = waiterCountWaiters
                waiterCountWaiters.removeAll()
                for waiter in ready {
                    waiter.resume()
                }
            }
        }, onCancel: {
            Task { await self.cancelAll() }
        })
    }

    func waitUntilSleeping() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { continuation in
            waiterCountWaiters.append(continuation)
        }
    }

    func isSleeping() -> Bool {
        !waiters.isEmpty
    }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancelAll() {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume(throwing: CancellationError())
        }
    }
}

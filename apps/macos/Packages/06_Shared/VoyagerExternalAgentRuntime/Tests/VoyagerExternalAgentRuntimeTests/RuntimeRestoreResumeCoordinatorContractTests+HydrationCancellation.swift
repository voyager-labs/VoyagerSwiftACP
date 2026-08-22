import Foundation
import os
import Testing
@testable import VoyagerExternalAgentRuntime

/// waiter 완료 신호를 구조적 join 없이 관찰하기 위한 Sendable 스냅샷.
private enum HydrationWaiterEscape: Equatable {
    case completed
    case failed(isCancellation: Bool)
}

/// 모니터 태스크가 기록하고 폴링 루프가 읽는 경계 상자.
private final class HydrationWaiterEscapeBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<HydrationWaiterEscape?>(initialState: nil)

    func store(_ value: HydrationWaiterEscape) {
        lock.withLock { $0 = value }
    }

    var latest: HydrationWaiterEscape? {
        lock.withLock { $0 }
    }
}

extension RuntimeRestoreResumeCoordinatorContractTests {
    /// VOY-747-hydration_cancellation: a cancelled hydration waiter escapes without the shared load finishing.
    /// 공유 hydration load가 진행 중이어도 개별 waiter는 자신의 취소를 즉시 관찰해야 함을 고정한다.
    /// - 검증 내용: waiter 취소 시 CancellationError 즉시 반환, waiter count 정리, 공유 load와 타 waiter 무영향.
    /// - 사전 조건: load gate로 막힌 공유 hydration과 이에 합류한 두 번째 waiter가 있다.
    /// - 기대 결과: load gate를 열기 전에 waiter가 CancellationError로 종료되고 count는 1로 유지된다.
    @Test
    func `hydration waiter returns promptly on caller cancellation`() async throws {
        enum PrelaunchOutcome {
            case completed
            case failed(Error)
        }

        let loadGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(loadGates: [1: loadGate])
        let plane = RuntimeControlPlane(store: store)
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        try await plane.register(adapter)
        let first = makeLaunch(host: "host-hydration-a", run: RuntimeRunReference("run-hydration-a"), adapterID: "sdk")
        let second = makeLaunch(host: "host-hydration-b", run: RuntimeRunReference("run-hydration-b"), adapterID: "sdk")

        let leaderTask = Task { try await plane.projectPrelaunch(first, as: .policyReady) }
        await store.waitForLoadCount(1)

        let waiterTask = Task<PrelaunchOutcome, Never> {
            do {
                try await plane.projectPrelaunch(second, as: .policyReady)
                return .completed
            } catch {
                return .failed(error)
            }
        }
        // waiter가 공유 hydration에 합류해 대기 상태에 진입했음을 결정적으로 확인한다.
        while await plane.hydrationWaiterCount < 2 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        waiterTask.cancel()

        // task.value 대기는 취소되지 않으므로 구조적 그룹 join 대신 비구조 모니터 + bounded 폴링으로 관찰한다.
        let escapeBox = HydrationWaiterEscapeBox()
        let monitor = Task {
            let outcome = await waiterTask.value
            switch outcome {
            case .completed:
                escapeBox.store(.completed)
            case let .failed(error):
                escapeBox.store(.failed(isCancellation: error is CancellationError))
            }
        }

        var observed: HydrationWaiterEscape?
        for _ in 0 ..< 600 {
            if let value = escapeBox.latest {
                observed = value
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        guard let escape = observed else {
            #expect(Bool(false), "cancelled waiter must escape before the shared load gate opens")
            await loadGate.open()
            _ = try? await leaderTask.value
            _ = await monitor.value
            return
        }

        guard case .failed(true) = escape else {
            #expect(Bool(false), "cancelled waiter must fail with CancellationError before delivery")
            await loadGate.open()
            _ = try? await leaderTask.value
            _ = await monitor.value
            return
        }
        #expect(await plane.hydrationWaiterCount == 1, "only the leader remains waiting after cancellation")

        await loadGate.open()
        try await leaderTask.value
        _ = await monitor.value
        #expect(await plane.hydrationWaiterCount == 0)
    }
}

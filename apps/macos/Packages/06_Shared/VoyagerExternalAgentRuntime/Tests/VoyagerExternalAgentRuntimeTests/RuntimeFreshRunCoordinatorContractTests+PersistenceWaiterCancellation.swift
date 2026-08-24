import Foundation
import os
import Testing
@testable import VoyagerExternalAgentRuntime

/// persistence waiter 완료 신호를 구조적 join 없이 관찰하기 위한 Sendable 스냅샷.
private enum PersistenceWaiterEscape: Equatable {
    case completed
    case failed(isCancellation: Bool)
}

/// 모니터 태스크가 기록하고 폴링 루프가 읽는 경계 상자.
private final class PersistenceWaiterEscapeBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<PersistenceWaiterEscape?>(initialState: nil)

    func store(_ value: PersistenceWaiterEscape) {
        lock.withLock { $0 = value }
    }

    var latest: PersistenceWaiterEscape? {
        lock.withLock { $0 }
    }
}

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-747-persistence_waiter_cancellation: a cancelled persistence waiter escapes before the in-flight mutation
    /// completes.
    /// 진행 중인 persistence mutation이 save gate로 막혀 있어도 대기 중인 waiter는 자신의 취소를 즉시 관찰해야 함을 고정한다.
    /// - 검증 내용: waiter 취소 시 CancellationError 즉시 반환, 대기열 제거, store.apply 미실행, 이후 grant 경로 유지.
    /// - 사전 조건: save gate 뒤 mutation lock을 보유한 첫 번째 projectPrelaunch와 대기열에 진입한 두 번째 호출이 있다.
    /// - 기대 결과: gate를 열기 전에 waiter가 CancellationError로 종료하고 leader 저장과 후속 mutation은 정상 완료된다.
    @Test
    func `cancelled persistence waiter escapes before mutation completes`() async throws {
        enum PrelaunchOutcome {
            case completed
            case failed(Error)
        }

        let saveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [1: saveGate])
        let plane = RuntimeControlPlane(store: store)
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        try await plane.register(adapter)
        let hostA = ExternalAgentSessionReference("host-persistence-a")
        let hostB = ExternalAgentSessionReference("host-persistence-b")
        let hostC = ExternalAgentSessionReference("host-persistence-c")
        let leaderRequest = makeLaunch(host: hostA, run: RuntimeRunReference("run-persistence-a"), adapterID: "sdk")
        let waiterRequest = makeLaunch(host: hostB, run: RuntimeRunReference("run-persistence-b"), adapterID: "sdk")

        // leader가 mutation lock을 보유한 채 gated apply 안에 진입했음을 결정적으로 확인한다.
        let leaderTask = Task { try await plane.projectPrelaunch(leaderRequest, as: .policyReady) }
        await store.waitForSaveCount(1)

        let waiterTask = Task<PrelaunchOutcome, Never> {
            do {
                try await plane.projectPrelaunch(waiterRequest, as: .policyReady)
                return .completed
            } catch {
                return .failed(error)
            }
        }
        // waiter가 persistence mutation 대기열에 진입했음을 bounded 폴링으로 확인한다.
        var queued = false
        for _ in 0 ..< 600 {
            if await plane.persistenceMutationWaiterCount >= 1 {
                queued = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(queued, "second prelaunch must queue on the persistence mutation lock")

        waiterTask.cancel()

        // task.value 대기는 취소되지 않으므로 구조적 그룹 join 대신 비구조 모니터 + bounded 폴링으로 관찰한다.
        let escapeBox = PersistenceWaiterEscapeBox()
        let monitor = Task {
            let outcome = await waiterTask.value
            switch outcome {
            case .completed:
                escapeBox.store(.completed)
            case let .failed(error):
                escapeBox.store(.failed(isCancellation: error is CancellationError))
            }
        }

        var observed: PersistenceWaiterEscape?
        for _ in 0 ..< 600 {
            if let value = escapeBox.latest {
                observed = value
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        guard let escape = observed else {
            #expect(Bool(false), "cancelled persistence waiter must escape before the gated apply finishes")
            await saveGate.open()
            _ = try? await leaderTask.value
            _ = await monitor.value
            return
        }

        guard case .failed(true) = escape else {
            #expect(Bool(false), "cancelled persistence waiter must fail with CancellationError before grant")
            await saveGate.open()
            _ = try? await leaderTask.value
            _ = await monitor.value
            return
        }

        // 취소된 waiter는 저장을 수행하지 않고 세션 상태에 흔적을 남기지 않는다.
        #expect(await store.applyCount == 1, "cancelled waiter must never reach store.apply")
        #expect(await plane.sessions[hostB] == nil, "cancelled host must stay absent from sessions")

        await saveGate.open()
        try await leaderTask.value
        _ = await monitor.value

        // leader 저장이 반영되고 취소 이후 grant 경로가 유지된다.
        let persisted = try #require(await store.currentState())
        #expect(persisted.sessions.count == 1)
        #expect(persisted.sessions.first?.externalAgentSessionReference == hostA)
        #expect(await plane.projection(for: hostA) == .policyReady)

        let followUpRequest = makeLaunch(host: hostC, run: RuntimeRunReference("run-persistence-c"), adapterID: "sdk")
        try await plane.projectPrelaunch(followUpRequest, as: .policyReady)
        #expect(await plane.projection(for: hostC) == .policyReady)
    }
}

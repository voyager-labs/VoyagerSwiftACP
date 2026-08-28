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

/// 모니터 태스크가 전달하는 waiter 완료 래퍼.
private enum HydrationWaiterResult {
    case completed
    case failed(Error)
}

/// 마지막 waiter 취소가 실제 공유 load 태스크로 전달되는지 관찰하는 테스트 전용 스토어.
/// 게이트 대기 자체는 취소 비협조적이고, 게이트가 열린 뒤에만 Task.isCancelled를 관찰한다.
private actor HydrationLoadCancellationObservingStore: RuntimeStateStore {
    let loadGate: RuntimeTestGate
    private(set) var loadCount = 0
    private(set) var loadSawCancellation = false
    private var loadCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(loadGate: RuntimeTestGate) {
        self.loadGate = loadGate
    }

    func load() async throws -> RuntimeStoredState? {
        loadCount += 1
        resumeLoadCountWaiters()
        // RuntimeStateStore 프로토콜은 취소 협조를 보장하지 않으므로 게이트 대기는 취소를 무시한다.
        await loadGate.wait()
        // 게이트가 열린 뒤에만 취소를 관찰해 load 태스크로의 전달 여부를 기록한다.
        if Task.isCancelled {
            loadSawCancellation = true
            throw CancellationError()
        }
        return nil
    }

    func apply(_: RuntimeStateMutation) async throws -> RuntimeStateMutationResult {
        // 이 계약 시나리오에서는 mutation이 발생하지 않는다.
        throw RuntimeStateStoreError.unavailable
    }

    func waitForLoadCount(_ minimumCount: Int) async {
        guard loadCount < minimumCount else { return }
        await withCheckedContinuation { continuation in
            loadCountWaiters.append((minimumCount, continuation))
        }
    }

    private func resumeLoadCountWaiters() {
        let ready = loadCountWaiters.filter { $0.0 <= loadCount }
        loadCountWaiters.removeAll { $0.0 <= loadCount }
        for (_, continuation) in ready {
            continuation.resume()
        }
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

    /// waiter 태스크가 CancellationError로 탈출하는지 bounded 폴링으로 관찰한다.
    private func observeWaiterCancellationEscape(_ task: Task<HydrationWaiterResult, Never>) async -> Bool {
        let escapeBox = HydrationWaiterEscapeBox()
        let monitor = Task {
            switch await task.value {
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
        _ = await monitor.value
        guard case .failed(true) = observed else { return false }
        return true
    }

    /// 결과 펌프가 task.result 이후 스스로 제거되기를 bounded 폴링으로 기다린다.
    private func waitForHydrationPumpRemoval(
        _ plane: RuntimeControlPlane,
        generation: UInt64,
    ) async -> Bool {
        for _ in 0 ..< 600 {
            if await plane.hydrationResultPumps[generation] == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    /// VOY-747-hydration_last_waiter_teardown: 마지막 현재 세대 waiter의 취소가 실제 공유 load 태스크 취소로 이어지는지 검증한다.
    /// - 검증 내용: 마지막 waiter의 즉시 CancellationError 탈출, hydrationTask 참조 정리, 게이트 폐쇄 중 결과 펌프 유지,
    ///   게이트 개방 후 task.result 기반 펌프 자기 제거, load 태스크 취소 전달 관찰, 신규 세대 재시도 성공.
    /// - 사전 조건: 취소 비협조적 load 게이트 뒤에서 단일 waiter가 현재 세대 공유 hydration을 기다린다.
    /// - 기대 결과: waiter는 게이트 개방 전 CancellationError로 탈출하고 load는 취소를 관찰하며,
    ///   펌프는 task.result 이후 스스로 제거된 뒤 새 세대 hydration이 성공한다.
    @Test
    func `final current-generation waiter cancellation cancels shared load and pump self cleans`() async throws {
        let loadGate = RuntimeTestGate()
        let store = HydrationLoadCancellationObservingStore(loadGate: loadGate)
        let plane = RuntimeControlPlane(store: store)

        let waiterTask = Task<HydrationWaiterResult, Never> {
            do {
                try await plane.hydrateIfNeeded()
                return .completed
            } catch {
                return .failed(error)
            }
        }
        await store.waitForLoadCount(1)
        let generation = await plane.hydrationGeneration

        waiterTask.cancel()
        guard await observeWaiterCancellationEscape(waiterTask) else {
            #expect(Bool(false), "마지막 waiter는 게이트 개방 전에 CancellationError로 탈출해야 한다")
            await loadGate.open()
            return
        }

        #expect(await plane.hydrationWaiterCount == 0, "마지막 waiter 탈출 뒤 waiter 수는 0이다")
        #expect(await plane.hydrationTask == nil, "현재 세대 hydrationTask 참조는 정리된다")
        #expect(
            await plane.hydrationResultPumps[generation] != nil,
            "게이트가 닫힌 동안 결과 펌프는 task.result를 기다리며 유지된다",
        )

        await loadGate.open()
        #expect(
            await waitForHydrationPumpRemoval(plane, generation: generation),
            "결과 펌프는 task.result 이후 스스로 제거된다",
        )
        #expect(
            await store.loadSawCancellation,
            "마지막 waiter 취소는 실제 공유 load 태스크에 취소를 요청해야 한다",
        )

        // 재시도: 참조가 정리되었으므로 새 세대 hydration이 성공해야 한다.
        try await plane.hydrateIfNeeded()
        #expect(await plane.hydrated)
        #expect(await plane.hydrationInstallCount == 1)
    }

    /// VOY-747-hydration_last_waiter_teardown: 마지막이 아닌 waiter의 취소는 공유 load를 유지해야 한다.
    /// - 검증 내용: 남은 waiter의 성공 설치, 단일 load와 단일 install, load 취소 미관찰, 펌프 자기 제거.
    /// - 사전 조건: 두 waiter가 동일한 gated load를 공유하고 follower만 먼저 취소된다.
    /// - 기대 결과: follower는 즉시 CancellationError로 탈출하고 leader는 공유 load로 한 번 설치한다.
    @Test
    func `non-last waiter cancellation keeps shared load alive for remaining waiter`() async throws {
        let loadGate = RuntimeTestGate()
        let store = HydrationLoadCancellationObservingStore(loadGate: loadGate)
        let plane = RuntimeControlPlane(store: store)

        let leaderTask = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)
        let followerTask = Task<HydrationWaiterResult, Never> {
            do {
                try await plane.hydrateIfNeeded()
                return .completed
            } catch {
                return .failed(error)
            }
        }
        await plane.waitForHydrationWaiters(2)
        let generation = await plane.hydrationGeneration

        followerTask.cancel()
        guard await observeWaiterCancellationEscape(followerTask) else {
            #expect(Bool(false), "follower waiter는 게이트 개방 전에 CancellationError로 탈출해야 한다")
            await loadGate.open()
            _ = try? await leaderTask.value
            return
        }

        #expect(await plane.hydrationWaiterCount == 1, "leader만 남아 대기한다")
        #expect(await plane.hydrationTask != nil, "마지막이 아닌 waiter 취소는 공유 load 참조를 유지한다")
        #expect(await plane.hydrationResultPumps[generation] != nil)

        await loadGate.open()
        try await leaderTask.value

        #expect(await store.loadSawCancellation == false, "남은 waiter가 있는 동안 공유 load는 취소되지 않는다")
        #expect(await store.loadCount == 1, "공유 load는 정확히 한 번 실행된다")
        #expect(await plane.hydrationInstallCount == 1, "설치는 leader에 의해 정확히 한 번 일어난다")
        #expect(await plane.hydrationResultPumps[generation] == nil, "설치 후 결과 펌프는 스스로 제거된다")
    }
}

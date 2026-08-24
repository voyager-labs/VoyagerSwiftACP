import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-746-launch_cancellation: caller cancellation during reservation persistence skips provider launch.
    /// 예약 저장 대기 중 호출자가 취소되면 provider launch 진입 자체가 없어야 함을 고정한다.
    /// - 검증 내용: 취소 관찰 후 CancellationError 반환, launch 0회, durable .launchCancelled 수렴과 비활성 lease.
    /// - 사전 조건: policy-ready run과 reservation save gate가 구성되고 launch gate는 열지 않는다.
    /// - 기대 결과: run이 CancellationError로 종료되고 adapter.launch는 호출되지 않는다.
    @Test
    func `caller cancellation before provider launch skips provider side effect`() async throws {
        let host: ExternalAgentSessionReference = "host-prelaunch-cancel"
        let run = RuntimeRunReference("run-prelaunch-cancel")
        let reservationGate = RuntimeTestGate()
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore(saveGates: [2: reservationGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await store.waitForSaveCount(2)
        runTask.cancel()

        await reservationGate.open()

        // 결정적 완료 신호: 취소 전환의 durable 수렴(.launchCancelled)을 bounded 폴링으로 대기한다.
        var converged = false
        for _ in 0 ..< 600 {
            if let session = await store.currentState()?.sessions
                .first(where: { $0.externalAgentSessionReference == host }),
                session.projection == .launchCancelled
            {
                converged = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(converged, "caller-cancel transition must converge to .launchCancelled without opening the launch gate")
        // 수렴 실패 시 runTask가 launch gate에 막혀 있어 await하면 테스트가 정지한다. RED 관측 후 즉시 종료시킨다.
        guard converged else {
            await launchGate.open()
            _ = try? await runTask.value
            return
        }

        #expect(
            await adapter.counts().launch == 0,
            "provider launch entry point must not be reached after cancellation",
        )
        let storedSession = await store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host })
        #expect(storedSession?.runReference == run)

        await #expect(throws: CancellationError.self) {
            try await runTask.value
        }

        await launchGate.open()
    }

    /// VOY-747-receipt_cancel_boundary: caller cancellation during receipt apply detaches before provider consumption.
    /// receipt 저장 apply가 gate로 막힌 동안의 caller 취소가 provider 소비 시작 전에 canonical 탈출하는지 고정한다.
    /// - 검증 내용: stream gate 개방 전 CancellationError 탈출, eventStream 0회, durable running+receipt projection,
    /// detachedConsuming lease, launch 1회.
    /// - 사전 조건: receipt apply(save 3)가 gate에서 대기하는 동안 caller가 취소된다.
    /// - 기대 결과: gate 개방 뒤 run은 provider event stream을 만들지 않고 CancellationError로 끝나며 소유권은 detached consuming이 된다.
    @Test
    func `caller cancellation during receipt apply detaches before provider consumption`() async throws {
        let host: ExternalAgentSessionReference = "host-receipt-cancel-boundary"
        let run = RuntimeRunReference("run-receipt-cancel-boundary")
        let receiptGate = RuntimeTestGate()
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore(saveGates: [3: receiptGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await store.waitForSaveCount(3)
        runTask.cancel()
        await receiptGate.open()

        // run 종료를 비구조 모니터 + bounded 폴링으로 관찰한다(막힌 provider로 테스트가 정지하지 않게).
        let recorder = ResumeProbeRecorder()
        let monitor = Task {
            do {
                try await recorder.record(.result(runTask.value))
            } catch is CancellationError {
                await recorder.record(.cancellation)
            } catch {
                await recorder.record(.failure(String(describing: error)))
            }
        }
        var observed = false
        for _ in 0 ..< 600 {
            if await recorder.waitForValue(maxYields: 1) {
                observed = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard observed, await recorder.value == .cancellation else {
            Issue.record("receipt 저장 이후 취소는 stream gate 개방 없이 CancellationError로 탈출해야 한다")
            await streamGate.open()
            _ = await monitor.value
            return
        }

        #expect(await adapter.counts().launch == 1)
        #expect(await adapter.counts().stream == 0, "provider event stream은 생성되지 않아야 한다")
        let stored = try #require(await store.currentState()?.sessions.first(where: {
            $0.externalAgentSessionReference == host
        }))
        #expect(stored.projection == .running)
        #expect(stored.providerInternalSessionReference != nil, "durable state는 검증된 receipt를 보존해야 한다")
        let session = try #require(await plane.sessions[host])
        guard case .detachedConsuming = session.lease else {
            Issue.record("receipt 저장 이후 취소는 detached consuming 소유자를 남겨야 한다: \(session.lease)")
            await streamGate.open()
            _ = await monitor.value
            return
        }

        await streamGate.open()
        _ = await monitor.value
    }
}

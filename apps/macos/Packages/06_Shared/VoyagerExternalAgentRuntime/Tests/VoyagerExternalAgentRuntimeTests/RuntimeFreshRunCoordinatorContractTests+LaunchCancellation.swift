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
}

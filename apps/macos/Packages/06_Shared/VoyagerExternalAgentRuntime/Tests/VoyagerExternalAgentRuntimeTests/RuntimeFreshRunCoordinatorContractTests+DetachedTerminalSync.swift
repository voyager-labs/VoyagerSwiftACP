import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-747-detached_terminal_sync: detached consuming owner adopts cross-plane terminal for replacement.
    /// 소유자 작업이 사라진 detachedConsuming 소유자가 다른 평면이 저장한 host terminal을 교체 prelaunch 전에 채택하는지 검증한다.
    /// - 검증 내용: 교체 전 동기화로 local projection이 completed로 수렴하고 lease가 해제되며, 같은 host의 교체 prelaunch가 성공한다.
    /// - 사전 조건: 공유 store를 쓰는 두 평면 중 A가 receipt 이후 caller cancel로 detachedConsuming 소유자를 남기고 B가 같은 run의
    ///   host terminal을 저장한다.
    /// - 기대 결과: 교체 prelaunch는 activeRunExists 없이 성공하고 store는 교체 run의 policyReady로 수렴한다.
    @Test
    func `detached consuming owner adopts cross-plane terminal for replacement`() async throws {
        let host: ExternalAgentSessionReference = "host-detached-terminal-sync"
        let firstRun = RuntimeRunReference("run-detached-terminal-sync-first")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let fixture = try await detachedTerminalSyncFixture(
            host: host,
            adapter: adapter,
            prelaunchRun: firstRun,
        )

        let runTask = Task { try await fixture.planeA.run(fixture.request) }
        // 결정적 취소 시점: receipt 저장(save 3)까지 대기한 뒤 caller cancel을 선형화한다.
        await fixture.store.waitForSaveCount(3)
        runTask.cancel()

        await #expect(throws: CancellationError.self) {
            try await runTask.value
        }
        let detachedSession = try #require(await fixture.planeA.sessions[host])
        guard case .detachedConsuming = detachedSession.lease else {
            Issue.record("receipt 이후 caller cancel은 detachedConsuming 소유자를 남겨야 한다: \(detachedSession.lease)")
            await streamGate.open()
            return
        }
        #expect(detachedSession.stored.projection == .running)
        try await assertCrossPlaneTerminalAdoption(
            fixture: fixture,
            replacementRun: RuntimeRunReference("run-detached-terminal-sync-replacement"),
        )
        await streamGate.open()
    }

    /// VOY-747-detached_terminal_sync: detached launching owner adopts cross-plane terminal for replacement.
    /// 취소 저장 실패로 남은 detachedLaunching 소유자도 교체 prelaunch 전에 cross-plane host terminal을 채택하는지 검증한다.
    /// - 검증 내용: 채택 뒤 local projection completed와 lease 해제, 같은 host 교체 prelaunch 성공과 store 수렴.
    /// - 사전 조건: receipt 저장 실패(failingSaveNumbers [3])로 detachedLaunching이 남고 평면 B가 같은 run의 host terminal을 저장한다.
    /// - 기대 결과: 교체 prelaunch는 성공하고 store는 교체 run의 policyReady로 수렴한다.
    @Test
    func `detached launching owner adopts cross-plane terminal for replacement`() async throws {
        let host: ExternalAgentSessionReference = "host-detached-launch-sync"
        let firstRun = RuntimeRunReference("run-detached-launch-sync-first")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let fixture = try await detachedTerminalSyncFixture(
            host: host,
            adapter: adapter,
            prelaunchRun: firstRun,
            failingSaveNumbers: [3],
        )

        let runTask = Task { try await fixture.planeA.run(fixture.request) }
        await adapter.waitForLaunchCount(1)
        runTask.cancel()
        await launchGate.open()

        await #expect(throws: CancellationError.self) {
            try await runTask.value
        }
        let detachedSession = try #require(await fixture.planeA.sessions[host])
        guard case .detachedLaunching = detachedSession.lease else {
            Issue.record("취소 저장 실패 뒤 launch owner는 detachedLaunching이어야 한다: \(detachedSession.lease)")
            return
        }
        try await assertCrossPlaneTerminalAdoption(
            fixture: fixture,
            replacementRun: RuntimeRunReference("run-detached-launch-sync-replacement"),
        )
    }

    // MARK: - Helpers

    private struct DetachedTerminalSyncFixture {
        let store: InMemoryRuntimeStateStore
        let planeA: RuntimeControlPlane
        let planeB: RuntimeControlPlane
        let request: RuntimeLaunchRequest
    }

    private func detachedTerminalSyncFixture(
        host: ExternalAgentSessionReference,
        adapter: DeterministicRuntimeAdapter,
        prelaunchRun: RuntimeRunReference,
        failingSaveNumbers: Set<Int> = [],
    ) async throws -> DetachedTerminalSyncFixture {
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: failingSaveNumbers)
        let planeA = RuntimeControlPlane(store: store)
        let planeB = RuntimeControlPlane(store: store)
        try await planeA.register(adapter)
        let request = makeLaunch(host: host, run: prelaunchRun, adapterID: "sdk")
        try await planeA.projectPrelaunch(request, as: .policyReady)
        return DetachedTerminalSyncFixture(store: store, planeA: planeA, planeB: planeB, request: request)
    }

    /// 공유 store 위에서 평면 B가 host terminal을 저장하고, 평면 A의 교체 prelaunch 동기화가 이를 채택했는지 관찰한다.
    private func assertCrossPlaneTerminalAdoption(
        fixture: DetachedTerminalSyncFixture,
        replacementRun: RuntimeRunReference,
    ) async throws {
        let host = fixture.request.externalAgentSessionReference
        let terminal = try #require(try await fixture.planeB.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: fixture.request.runReference,
            sequence: 1,
        )))
        #expect(terminal.outcome == .completed)
        let persistedTerminal = try #require(await fixture.store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host }))
        #expect(persistedTerminal.projection == .completed)

        // 동기화 관찰: 커밋 이전에 동기화가 실행되므로 미등록 어댑터 요청은 채택 후 어댑터 오류로 실패한다.
        do {
            try await fixture.planeA.projectPrelaunch(
                makeLaunch(
                    host: host,
                    run: RuntimeRunReference("\(replacementRun.rawValue)-probe"),
                    adapterID: "missing",
                ),
                as: .policyReady,
            )
            Issue.record("미등록 어댑터 요청은 실패해야 한다")
        } catch {
            // 동기화는 커밋 검증보다 먼저 실행되므로 오류 종류와 무관하게 채택 결과를 관찰한다.
        }
        #expect(await fixture.planeA.projection(for: host) == .completed)
        #expect(await fixture.planeA.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)

        try await fixture.planeA.projectPrelaunch(
            makeLaunch(host: host, run: replacementRun, adapterID: "sdk"),
            as: .policyReady,
        )
        let replaced = try #require(await fixture.store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host }))
        #expect(replaced.runReference == replacementRun)
        #expect(replaced.projection == .policyReady)
        #expect(await fixture.planeA.projection(for: host) == .policyReady)
        #expect(await fixture.planeA.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
    }
}

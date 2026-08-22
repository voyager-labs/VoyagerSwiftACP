import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-747-terminal_lease_hold: decision table caller-cancel release rows lock ownership-only release.
    /// terminal 스냅샷에서 caller cancel 결정이 consuming 소유자의 소유권만 해제하는 표 벡터를 고정한다.
    /// - 검증 내용: consuming(9) 소유자는 persist(동일 projection, 첨부 receipt 없음, none)로 해제되고 detachedConsuming(9)는 ignore다.
    /// - 사전 조건: completed projection과 receipt token을 가진 decision-table 스냅샷 벡터를 직접 구성한다.
    /// - 기대 결과: consuming 소유자의 취소는 소유권만 해제하고 detached 소유자의 취소는 상태를 바꾸지 않는다.
    @Test
    func `decision table releases held consumption owner on terminal caller cancel`() {
        let snapshot = RuntimeFreshRunSnapshot(
            projection: .completed,
            receiptToken: "receipt-terminal",
            lease: .consuming(9),
            runReference: RuntimeRunReference("run-decision-table"),
        )
        #expect(RuntimeFreshRunDecisionTable.decide(.callerCancel, on: snapshot)
            == .persist(projection: .completed, attachReceipt: nil, lease: .none))
        let detached = RuntimeFreshRunSnapshot(
            projection: .completed,
            receiptToken: "receipt-terminal",
            lease: .detachedConsuming(9),
            runReference: RuntimeRunReference("run-decision-table"),
        )
        #expect(RuntimeFreshRunDecisionTable.decide(.callerCancel, on: detached) == .ignore)
    }

    /// VOY-747-terminal_lease_hold: terminal event holds consumption lease until result reconciles.
    /// provider terminal event 저장 후에도 결과 수렴 전까지 consuming 소유권이 유지되는지 고정한다.
    /// - 검증 내용: terminal event 저장 직후 consuming lease 유지, 같은 host 교체 prelaunch 거부, gate 개방 뒤 canonical 결과와 lease 해제.
    /// - 사전 조건: terminal-only 결과 gate가 닫힌 SDK transport run이 completed provider event를 먼저 저장한다.
    /// - 기대 결과: terminal event 이후 consuming lease가 유지되고 교체 prelaunch는 activeRunExists로 거부되며 결과 수렴 뒤 lease가 해제된다.
    @Test
    func `terminal event holds consumption lease until result reconciles`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-lease-window"
        let run = RuntimeRunReference("run-terminal-lease-window")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-lease-window",
                kind: .completed,
            )]],
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }

        // 결정적 완료 신호: provider terminal event의 durable 저장을 bounded 폴링으로 대기한다.
        let converged = await waitForDurableProjection(.completed, host: host, store: store)
        #expect(converged, "provider terminal event must be durably stored while the result gate stays closed")

        // terminal event 이후에도 결과 수렴 전까지 consuming 소유권이 유지되어야 한다.
        let heldLease = await plane.sessions[host]?.lease ?? .none
        guard case .consuming = heldLease else {
            Issue.record("terminal event 저장 후에도 consuming lease가 유지되어야 한다: \(heldLease)")
            // RED 관측 시 runTask가 결과 gate에 막혀 있으므로 즉시 개방하고 종료한다.
            await resultGate.open()
            _ = try? await runTask.value
            return
        }

        // consuming 소유권이 유지되는 동안 같은 host의 교체 prelaunch는 거부된다.
        let replacementRequest = makeLaunch(
            host: host,
            run: RuntimeRunReference("run-terminal-lease-window-replacement"),
            adapterID: "sdk",
        )
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await plane.projectPrelaunch(replacementRequest, as: .policyReady)
        }

        await resultGate.open()

        #expect(try await runTask.value.outcome == .completed)
        // Optional(RuntimeLease) 비교에서 .none 리터럴은 Optional.none으로 묶이므로 정규화된 케이스로 비교한다.
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-747-terminal_lease_cancel_release: caller cancellation during terminal result window releases held
    /// consumption owner.
    /// terminal 결과 대기 창에서 늦은 caller 취소가 저장된 terminal로 수렴하고 소유권을 해제함을 고정한다.
    /// - 검증 내용: 취소 후에도 completed 결과 정상 반환, durable projection 유지, lease 해제와 교체 prelaunch 성공.
    /// - 사전 조건: terminal-only 결과 gate가 닫힌 run이 completed provider event를 저장하고 consuming lease를 유지한다.
    /// - 기대 결과: 취소된 caller도 converged completed를 받고 lease는 해제되어 같은 host 교체 prelaunch가 성공한다.
    @Test
    func `caller cancellation during terminal result window releases held consumption owner`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-lease-cancel"
        let run = RuntimeRunReference("run-terminal-lease-cancel")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-lease-cancel",
                kind: .completed,
            )]],
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }

        // 결정적 완료 신호: provider terminal event의 durable 저장을 bounded 폴링으로 대기한다.
        let converged = await waitForDurableProjection(.completed, host: host, store: store)
        #expect(converged, "provider terminal event must be durably stored while the result gate stays closed")

        // 늦은 취소 수렴 불변식을 관찰하기 위해 보유 중인 lease를 기록한다.
        let heldLease = await plane.sessions[host]?.lease

        runTask.cancel()
        await resultGate.open()

        // 수렴 의미론: 취소된 caller도 이미 저장된 terminal 결과를 정상 반환으로 수령한다.
        #expect(try await runTask.value.outcome == .completed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)

        // 소유권 해제를 bounded 폴링으로 대기한다.
        var released = false
        for _ in 0 ..< 600 {
            if await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none {
                released = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(released, "late cancellation must end with released ownership, held=\(String(describing: heldLease))")

        // 해제 뒤 같은 host 교체 prelaunch가 성공해야 한다(교체 선점 불변식).
        let replacementRequest = makeLaunch(
            host: host,
            run: RuntimeRunReference("run-terminal-lease-cancel-replacement"),
            adapterID: "sdk",
        )
        try await plane.projectPrelaunch(replacementRequest, as: .policyReady)
        #expect(await plane.projection(for: host) == .policyReady)
    }

    private func waitForDurableProjection(
        _ expected: RuntimeProjection,
        host: ExternalAgentSessionReference,
        store: InMemoryRuntimeStateStore,
    ) async -> Bool {
        for _ in 0 ..< 600 {
            if let session = await store.currentState()?.sessions
                .first(where: { $0.externalAgentSessionReference == host }),
                session.projection == expected
            {
                return true
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }
}

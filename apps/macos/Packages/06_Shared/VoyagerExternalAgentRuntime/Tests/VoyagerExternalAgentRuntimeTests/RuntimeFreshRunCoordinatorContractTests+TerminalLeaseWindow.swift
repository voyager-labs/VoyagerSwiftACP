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

    /// VOY-747-reconcile_ownership: same-run live owner survives a full snapshot reconcile.
    /// 전체 스냅샷 재조정이 같은 run의 live 소유자 lease/revision을 보존하는지 고정한다.
    /// - 검증 내용: 무관 host commit 뒤에도 consuming lease/revision 유지, terminal 채택, 교체 prelaunch activeRunExists 거부와 수렴 후 성공.
    /// - 사전 조건: plane A가 host B run을 consuming 소유한 채 결과 gate에서 대기하고 plane B가 같은 run의 completed terminal을 저장한다.
    /// - 기대 결과: 재조정 후에도 B는 terminal을 채택하되 정확한 consuming lease/revision을 유지하고 원래 수렴 전에는 교체가 거부된다.
    @Test
    func `same run consuming owner survives unrelated snapshot reconcile`() async throws {
        let hostA: ExternalAgentSessionReference = "host-reconcile-owner-a"
        let hostB: ExternalAgentSessionReference = "host-reconcile-owner-b"
        let runB = RuntimeRunReference("run-reconcile-owner-b")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore()
        let planeA = RuntimeControlPlane(store: store)
        let planeB = RuntimeControlPlane(store: store)
        try await planeA.register(adapter)
        try await planeB.register(adapter)
        let requestB = makeLaunch(host: hostB, run: runB, adapterID: "terminal")
        try await planeA.projectPrelaunch(requestB, as: .policyReady)

        let runTaskB = Task { try await planeA.run(requestB) }
        await adapter.waitForTerminalResultCount(1)

        // 재조정 전 소유권 증거를 고정한다.
        let heldLease = try #require(await planeA.sessions[hostB]?.lease)
        guard case .consuming = heldLease else {
            Issue.record("결과 gate 대기 중 host B는 consuming 소유자여야 한다: \(heldLease)")
            await resultGate.open()
            _ = try? await runTaskB.value
            return
        }
        let heldRevision = try #require(await planeA.sessions[hostB]?.revision)

        // plane B가 같은 run의 host terminal을 저장한다.
        #expect(try await planeB.ingestHostEvent(makeReconcileHostCompletedEvent(
            host: hostB,
            run: runB,
        ))?.outcome == .completed)
        #expect(await waitForDurableProjection(.completed, host: hostB, store: store))

        // 무관 host A의 commit이 전체 스냅샷 재조정을 강제한다.
        try await planeA.projectPrelaunch(
            makeLaunch(host: hostA, run: RuntimeRunReference("run-reconcile-owner-a"), adapterID: "terminal"),
            as: .policyReady,
        )

        // 같은 run live 소유자는 저장 스냅샷이 바뀌어도 lease/revision을 보존한다.
        let reconciledSession = try #require(await planeA.sessions[hostB])
        #expect(reconciledSession.stored.projection == .completed, "저장된 terminal은 채택되어야 한다")
        #expect(reconciledSession.lease == heldLease, "consuming lease는 재조정 후에도 유지되어야 한다: \(reconciledSession.lease)")
        #expect(reconciledSession.revision == heldRevision, "revision은 재조정 후에도 유지되어야 한다")

        // 원래 run이 수렴하기 전까지 같은 host 교체 prelaunch는 거부된다.
        let replacementRequest = makeLaunch(
            host: hostB,
            run: RuntimeRunReference("run-reconcile-owner-b-replacement"),
            adapterID: "terminal",
        )
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await planeA.projectPrelaunch(replacementRequest, as: .policyReady)
        }

        await assertResetReconciliationVectors(
            plane: planeA,
            host: hostB,
            candidateStored: reconciledSession.stored,
        )

        // 원래 run 수렴 뒤에는 lease가 해제되고 교체 prelaunch가 성공한다.
        await resultGate.open()
        #expect(try await runTaskB.value.outcome == .completed)
        var released = false
        for _ in 0 ..< 600 {
            if await planeA.sessions[hostB]?.lease == RuntimeControlPlane.RuntimeLease.none {
                released = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(released, "원래 run 수렴 뒤 consuming 소유권은 해제되어야 한다")
        try await planeA.projectPrelaunch(replacementRequest, as: .policyReady)
        #expect(await planeA.projection(for: hostB) == .policyReady)
    }

    private func assertResetReconciliationVectors(
        plane: RuntimeControlPlane,
        host: ExternalAgentSessionReference,
        candidateStored: RuntimeStoredSession,
    ) async {
        let detachedCandidate: [ExternalAgentSessionReference: RuntimeControlPlane.Session] = [
            host: RuntimeControlPlane.Session(
                stored: candidateStored.withProjection(.running),
                lease: .detachedConsuming(7),
                revision: 3,
            ),
        ]
        let detachedReconciled = await plane.reconciledRegistry(
            candidate: detachedCandidate,
            persisted: makeState([candidateStored]),
        )
        #expect(
            detachedReconciled[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
            "detached 소유자는 저장 스냅샷 변경 시 초기화된다",
        )
        #expect(detachedReconciled[host]?.stored == candidateStored)

        let foreignStored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),
            runReference: RuntimeRunReference("run-reconcile-owner-foreign"),
            capabilitySnapshot: .terminalOnly,
            projection: .completed,
        )
        let foreignCandidate: [ExternalAgentSessionReference: RuntimeControlPlane.Session] = [
            host: RuntimeControlPlane.Session(
                stored: candidateStored,
                lease: .consuming(5),
                revision: 9,
            ),
        ]
        let foreignReconciled = await plane.reconciledRegistry(
            candidate: foreignCandidate,
            persisted: makeState([foreignStored]),
        )
        #expect(
            foreignReconciled[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
            "다른 run의 저장 스냅샷은 live 소유자도 초기화한다",
        )
        #expect(foreignReconciled[host]?.stored == foreignStored)
    }

    /// VOY-747-terminal_release_neutrality: terminal fast-path release lands despite caller cancellation.
    /// persistence lock 경합 중 caller 취소가 terminal 소유권 해제를 좌초시키지 않는지 고정한다.
    /// - 검증 내용: gate 해제 뒤 public completed 결과 유지, 정확한 target lease .none 해제와 교체 prelaunch 성공.
    /// - 사전 조건: target이 consuming 소유로 저장된 terminal에서 결과 fast-path에 진입하고 무관 host의 gated apply가 lock을 보유한다.
    /// - 기대 결과: caller 취소 후에도 해제는 반영되어 lease가 .none이 되고 같은 host 교체 prelaunch가 성공한다.
    @Test
    func `terminal fast-path release survives caller cancellation under lock contention`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-release-neutral"
        let run = RuntimeRunReference("run-terminal-release-neutral")
        let blockerHost: ExternalAgentSessionReference = "host-terminal-release-blocker"
        let resultGate = RuntimeTestGate()
        let blockerGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore(saveGates: [5: blockerGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "terminal")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForTerminalResultCount(1)

        // target 단말을 먼저 저장해 consuming 소유 + terminal 상태를 만든다.
        #expect(try await plane.ingestHostEvent(makeReconcileHostCompletedEvent(
            host: host,
            run: run,
        ))?.outcome == .completed)
        #expect(await waitForDurableProjection(.completed, host: host, store: store))

        // 무관 host의 gated apply가 persistence mutation lock을 보유한다.
        let blockerTask = Task {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: blockerHost,
                    run: RuntimeRunReference("run-terminal-release-blocker"),
                    adapterID: "terminal",
                ),
                as: .policyReady,
            )
        }
        await store.waitForSaveCount(5)

        // 결과 gate를 열어 target이 fast-path 해제를 시도하면 lock 대기열에 진입한다.
        await resultGate.open()
        var queued = false
        for _ in 0 ..< 600 {
            if await plane.persistenceMutationWaiterCount >= 1 {
                queued = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(queued, "fast-path release must queue on the persistence mutation lock")

        runTask.cancel()
        await blockerGate.open()

        // public terminal은 취소와 무관하게 completed로 수렴한다.
        #expect(try await runTask.value.outcome == .completed)

        // 취소된 caller 뒤에도 소유권 해제는 반드시 반영된다.
        var released = false
        for _ in 0 ..< 600 {
            if await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none {
                released = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard released else {
            await Issue
                .record(
                    "caller 취소 후에도 terminal 소유권 해제가 반영되어야 한다: \(String(describing: plane.sessions[host]?.lease))",
                )
            _ = try? await blockerTask.value
            return
        }

        // 해제 뒤 같은 host 교체 prelaunch가 성공한다.
        try await plane.projectPrelaunch(
            makeLaunch(
                host: host,
                run: RuntimeRunReference("run-terminal-release-neutral-replacement"),
                adapterID: "terminal",
            ),
            as: .policyReady,
        )
        #expect(await plane.projection(for: host) == .policyReady)
        _ = try? await blockerTask.value
    }

    private func makeReconcileHostCompletedEvent(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("reconcile-host-terminal"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("reconcile-host-terminal"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .completed,
        )
    }

    /// VOY-747-reconcile_ownership: every lease vector has explicit reconcile semantics.
    /// 전체 스냅샷 재조정에서 일곱 lease 케이스 각각의 보존/초기화 규칙을 벡터로 고정한다.
    /// - 검증 내용: 같은 run에서 launching/consuming과 owned-live claim의 restored/resuming은
    ///   lease/revision 보존, none/detached와 stale/foreign claim은 초기화, 다른 run 저장 스냅샷은 무조건 초기화.
    /// - 사전 조건: 후보 레지스트리가 각 lease의 소유자를 들고 있고 persisted 스냅샷이 같은 run에서 변경된다.
    /// - 기대 결과: 보존 벡터는 lease/revision을 유지하고 나머지는 Session(stored:)로 초기화되며 stored는 항상 persisted를 따른다.
    @Test(arguments: ReconcileOwnershipLeaseVector.allCases)
    func `snapshot reconcile applies explicit lease vector semantics`(
        vector: ReconcileOwnershipLeaseVector,
    ) async {
        let host = ExternalAgentSessionReference("host-reconcile-vector-\(vector.rawValue)")
        let run = RuntimeRunReference("run-reconcile-vector-\(vector.rawValue)")
        let foreignRun = RuntimeRunReference("run-reconcile-vector-foreign-\(vector.rawValue)")
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        let ownerToken = await plane.restorationOwnerToken
        let baseStored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            projection: .running,
            restorationClaim: vector.storedClaim(ownerToken: ownerToken),
        )
        let changedStored = baseStored.withProjection(.eventProjected)
        let candidate: [ExternalAgentSessionReference: RuntimeControlPlane.Session] = [
            host: RuntimeControlPlane.Session(
                stored: baseStored,
                lease: vector.lease,
                revision: 7,
            ),
        ]

        let reconciled = await plane.reconciledRegistry(
            candidate: candidate,
            persisted: makeState([changedStored]),
        )
        if vector.preservesSameRunOwner {
            #expect(reconciled[host]?.lease == vector.lease, "\(vector.rawValue)는 같은 run에서 보존된다")
            #expect(reconciled[host]?.revision == 7)
        } else {
            #expect(
                reconciled[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
                "\(vector.rawValue)는 같은 run에서도 초기화된다",
            )
        }
        #expect(reconciled[host]?.stored == changedStored, "저장 스냅샷은 항상 persisted 권위를 따른다")

        let foreignStored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: foreignRun,
            projection: .completed,
        )
        let foreignReconciled = await plane.reconciledRegistry(
            candidate: candidate,
            persisted: makeState([foreignStored]),
        )
        #expect(
            foreignReconciled[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
            "\(vector.rawValue)는 다른 run 저장 스냅샷에서 초기화된다",
        )
        #expect(foreignReconciled[host]?.stored == foreignStored)
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

    /// VOY-746-coordinator_contract: caller cancellation wins during provider failure cleanup.
    /// provider stream 오류를 정리하는 interrupt commit 전에 취소된 caller가 adapter 오류로 재분류되지 않는지 검증한다.
    /// - 검증 내용: public CancellationError, 배경 실패 수렴 뒤 durable interrupted와 lease 해제, redacted cleanup evidence.
    /// - 사전 조건: receipt-bearing stream이 gate 뒤 creation 오류를 내고 caller cancellation이 cleanup commit 전에 관찰된다.
    /// - 기대 결과: caller는 CancellationError를 받고 배경 드레인이 실패를 관찰해 interrupted로 수렴하며 소유권이 해제된다.
    @Test
    func `caller cancellation wins during provider failure cleanup`() async throws {
        let host: ExternalAgentSessionReference = "host-cleanup-caller-cancel"
        let run = RuntimeRunReference("run-cleanup-caller-cancel")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: .creation,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        runTask.cancel()
        await streamGate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }

        // 탈출 뒤 배경 드레인이 provider 실패를 관찰해 interrupt로 수렴하고 소유권을 해제한다.
        var converged = false
        for _ in 0 ..< 600 {
            if await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
               await plane.projection(for: host) == .interrupted
            {
                converged = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(converged, "배경 provider 실패는 interrupted 수렴과 소유권 해제로 관찰되어야 한다")
        #expect(await plane.cleanupFailureEvidence(for: host) == nil)
        #expect(await store.currentState()?.sessions.first?.projection == .interrupted)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: cancellation after receipt remains detached consumption.
    /// receipt commit 이후 consume 중 취소가 CancellationError로 끝나고 실패 terminal을 만들지 않는 미래 계약을 고정한다.
    /// - 검증 내용: public run CancellationError, 배경 수렴 뒤 failed/launchFailed가 아닌 terminal 수렴과 lease 해제.
    /// - 사전 조건: terminal-only adapter 결과가 gate에서 대기하는 receipt-bearing run이 있다.
    /// - 기대 결과: caller는 CancellationError를 받고 배경 provider 수렴 뒤 `.failed`가 아닌 completed로 마무리된다.
    @Test
    func `after-receipt cancel throws CancellationError without failed projection`() async throws {
        let host = ExternalAgentSessionReference("host-contract-after-receipt-cancel")
        let run = RuntimeRunReference("run-contract-after-receipt-cancel")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "terminal")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForTerminalResultCount(1)
        runTask.cancel()
        await resultGate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }

        // 탈출 뒤 배경 수렴이 완주되면 같은 run은 failed가 아닌 terminal로 수렴하고 소유권이 해제된다.
        var converged = false
        for _ in 0 ..< 600 {
            if await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none,
               await plane.projection(for: host) == .completed
            {
                converged = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(converged, "배경 provider 수렴 뒤 failed가 아닌 terminal로 마무리되어야 한다")
        let session = try #require(await plane.sessions[host])
        #expect(session.stored.projection != .failed)
        #expect(session.stored.projection != .launchFailed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().launch == 1)
    }
}

/// 재조정 소유권 벡터. 일곱 lease 케이스에 stale/foreign claim 변형을 더해 명시적 규칙을 만든다.
enum ReconcileOwnershipLeaseVector: String, CaseIterable {
    case none
    case launching
    case detachedLaunching
    case consuming
    case detachedConsuming
    case restoredOwnedLiveClaim
    case resumingOwnedLiveClaim
    case restoredForeignClaim
    case resumingExpiredOwnClaim

    var lease: RuntimeControlPlane.RuntimeLease {
        switch self {
        case .none: .none
        case .launching: .launching(4)
        case .detachedLaunching: .detachedLaunching(4)
        case .consuming: .consuming(4)
        case .detachedConsuming: .detachedConsuming(4)
        case .restoredOwnedLiveClaim, .restoredForeignClaim: .restored(4)
        case .resumingOwnedLiveClaim, .resumingExpiredOwnClaim: .resuming(4)
        }
    }

    var preservesSameRunOwner: Bool {
        switch self {
        case .launching, .consuming, .restoredOwnedLiveClaim, .resumingOwnedLiveClaim: true
        case .none, .detachedLaunching, .detachedConsuming, .restoredForeignClaim, .resumingExpiredOwnClaim:
            false
        }
    }

    func storedClaim(ownerToken: String) -> RuntimeRestorationClaim? {
        let farFuture = Date(timeIntervalSince1970: 4_102_444_800)
        switch self {
        case .restoredOwnedLiveClaim, .resumingOwnedLiveClaim:
            return RuntimeRestorationClaim(ownerToken: ownerToken, expiresAt: farFuture)
        case .restoredForeignClaim:
            return RuntimeRestorationClaim(ownerToken: "foreign-owner", expiresAt: farFuture)
        case .resumingExpiredOwnClaim:
            return RuntimeRestorationClaim(ownerToken: ownerToken, expiresAt: Date(timeIntervalSince1970: 1))
        case .none, .launching, .detachedLaunching, .consuming, .detachedConsuming:
            return nil
        }
    }
}

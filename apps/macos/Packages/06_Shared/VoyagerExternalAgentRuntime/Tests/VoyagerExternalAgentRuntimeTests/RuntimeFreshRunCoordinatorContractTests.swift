import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimeFreshRunCoordinatorContractTests")
struct RuntimeFreshRunCoordinatorContractTests {
    // MARK: - characterization-survivors

    /// VOY-746-characterization_survivors: reservation persistence completes before provider launch.
    /// 예약 저장이 완료되기 전에는 provider side effect가 시작되지 않는 현재 public run 순서를 고정한다.
    /// - 검증 내용: reservation save 대기 중 projection과 launch count, 저장 해제 후 완료 결과.
    /// - 사전 조건: policy-ready run과 reservation save gate가 구성되어 있다.
    /// - 기대 결과: reservation commit 전 launch는 0회이고 commit 후 정확히 1회 호출된다.
    @Test
    func `reservation persistence completes before provider launch`() async throws {
        let host: ExternalAgentSessionReference = "host-reservation-order"
        let run = RuntimeRunReference("run-reservation-order")
        let reservationGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let store = InMemoryRuntimeStateStore(saveGates: [2: reservationGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await store.waitForSaveCount(2)

        #expect(await plane.projection(for: host) == .policyReady)
        #expect(await adapter.counts().launch == 0)

        await reservationGate.open()
        await adapter.waitForLaunchCount(1)

        #expect(await adapter.counts().launch == 1)
        #expect(try await runTask.value.outcome == .completed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
    }

    /// VOY-746-characterization_survivors: a committed receipt blocks a duplicate launch.
    /// receipt commit 뒤 같은 runReference의 동시 재호출이 provider를 다시 시작하지 않는지 고정한다.
    /// - 검증 내용: receipt evidence, active consumption lease, duplicate run 오류와 launch count.
    /// - 사전 조건: receipt 이후 provider stream이 gate에서 대기하는 policy-ready run이 있다.
    /// - 기대 결과: 두 번째 run은 duplicateRunReference로 종료되고 launch는 정확히 1회다.
    @Test
    func `committed receipt blocks a duplicate launch`() async throws {
        let host: ExternalAgentSessionReference = "host-receipt-duplicate"
        let run = RuntimeRunReference("run-receipt-duplicate")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let firstRun = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)

        let stored = try #require(await plane.sessions[host]?.stored)
        #expect(stored.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
        #expect(stored.projection == .running)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await plane.run(request)
        }
        #expect(await adapter.counts().launch == 1)

        await streamGate.open()
        #expect(try await firstRun.value.outcome == .completed)
    }

    /// VOY-746-characterization_survivors: provider stream failure remains the public error.
    /// 이미 저장된 host terminal을 보존하되 provider stream 오류를 성공 결과로 변환하지 않는 계약을 고정한다.
    /// - 검증 내용: host terminal 저장 결과, provider stream failure의 원래 오류와 durable projection.
    /// - 사전 조건: provider stream failure가 gate 뒤 발생하고 그 전에 host completed event가 저장된다.
    /// - 기대 결과: adapter 오류가 그대로 전달되고 persisted completed projection과 launch 1회가 유지된다.
    @Test(arguments: [
        DeterministicRuntimeAdapter.EventStreamFailure.creation,
        .iteration,
    ])
    func `provider stream failure is not converted to persisted terminal success`(
        failure: DeterministicRuntimeAdapter.EventStreamFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-stream-terminal-\(failure)")
        let run = RuntimeRunReference("run-stream-terminal-\(failure)")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: failure,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)

        let hostResult = try await plane.ingestHostEvent(makeHostTerminalEvent(host: host, run: run))
        #expect(hostResult?.outcome == .completed)

        await streamGate.open()

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await runTask.value
        }
        #expect(await plane.projection(for: host) == .completed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-characterization_survivors: provider finish failure remains the public error.
    /// 이미 저장된 host terminal을 보존하되 terminal-result 오류를 성공 결과로 변환하지 않는 계약을 고정한다.
    /// - 검증 내용: terminal-result gate, host interrupted event 저장과 원래 provider 오류.
    /// - 사전 조건: terminal-only provider가 결과 조회에서 실패하고 그 전에 host terminal이 저장된다.
    /// - 기대 결과: adapter 오류가 그대로 전달되고 persisted interrupted projection과 launch 1회가 유지된다.
    @Test
    func `provider finish failure is not converted to persisted terminal success`() async throws {
        let host: ExternalAgentSessionReference = "host-finish-terminal"
        let run = RuntimeRunReference("run-finish-terminal")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
            failsTerminalResult: true,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "terminal")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForTerminalResultCount(1)

        let hostResult = try await plane.ingestHostEvent(makeHostTerminalEvent(
            host: host,
            run: run,
            kind: .interrupted,
        ))
        #expect(hostResult?.outcome == .interrupted)

        await resultGate.open()

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await runTask.value
        }
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await store.currentState()?.sessions.first?.projection == .interrupted)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-characterization_survivors: caller cancellation is not normalized as a host failure.
    /// provider launch 대기 중 caller 취소가 원래 CancellationError로 표면화되는 현재 경계를 고정한다.
    /// - 검증 내용: launch gate 이후 취소 오류의 실제 타입과 provider launch 호출 횟수.
    /// - 사전 조건: reservation이 완료되고 adapter launch가 gate에서 대기한다.
    /// - 기대 결과: caller는 CancellationError를 받고 adapter/host failure로 변환되지 않는다.
    @Test
    func `caller cancellation remains CancellationError`() async throws {
        let host: ExternalAgentSessionReference = "host-caller-cancellation"
        let run = RuntimeRunReference("run-caller-cancellation")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForLaunchCount(1)
        runTask.cancel()
        await launchGate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-characterization_survivors: cleanup persistence failure preserves the primary provider error and
    /// terminal.
    /// host terminal 이후 provider stream 오류의 cleanup 저장 실패가 원래 오류를 가리거나 terminal을 바꾸지 않는지 고정한다.
    /// - 검증 내용: provider 오류, cleanup 저장 실패의 redacted evidence와 최종 durable projection.
    /// - 사전 조건: host completed event 저장 후 terminal read와 cleanup write가 순서대로 실패한다.
    /// - 기대 결과: public run은 adapterUnavailable을 표면화하고 durable terminal은 completed로 유지되며 bounded evidence가 남는다.
    @Test
    func `cleanup failure keeps persisted terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-cleanup-terminal"
        let run = RuntimeRunReference("run-cleanup-terminal")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: .creation,
        )
        let store = InMemoryRuntimeStateStore(
            failingLoadNumbers: [2],
            failingSaveNumbers: [5],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)

        let hostResult = try await plane.ingestHostEvent(makeHostTerminalEvent(host: host, run: run))
        #expect(hostResult?.outcome == .completed)
        #expect(await store.saveCount == 4)

        await streamGate.open()

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await runTask.value
        }
        #expect(await adapter.counts().launch == 1)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await store.saveCount == 5)
        #expect(await store.applyCount == 5)
        #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
            runReference: run,
            kind: .persistence,
        ))
        #expect(await plane.sessions[host]?.lease.isActive == false)
    }

    /// VOY-746-coordinator_contract: cleanup failure evidence is bounded to the current run.
    /// 같은 host에서 replacement run을 예약하면 이전 cleanup failure evidence가 노출되지 않는지 검증한다.
    /// - 검증 내용: cleanup evidence의 run reference, replacement prelaunch 이후 evidence 초기화.
    /// - 사전 조건: 이전 run의 cleanup persistence failure가 redacted evidence를 남긴다.
    /// - 기대 결과: evidence는 host별 최신 1건이고 새 run 예약 시 제거된다.
    @Test
    func `cleanup failure evidence clears for a replacement run`() async throws {
        let host: ExternalAgentSessionReference = "host-cleanup-evidence-replacement"
        let run = RuntimeRunReference("run-cleanup-evidence-old")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: .creation,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [4])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        await streamGate.open()
        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await runTask.value
        }
        #expect(await plane.cleanupFailureEvidence(for: host)?.runReference == run)

        #expect(try await plane.ingestHostEvent(makeHostTerminalEvent(
            host: host,
            run: run,
            kind: .interrupted,
        ))?.outcome == .interrupted)
        let replacement = RuntimeRunReference("run-cleanup-evidence-replacement")
        let replacementGate = RuntimeTestGate()
        let replacementAdapter = DeterministicRuntimeAdapter(
            id: "replacement",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            launchGate: replacementGate,
        )
        try await plane.register(replacementAdapter)
        let replacementRequest = makeLaunch(host: host, run: replacement, adapterID: "replacement")
        try await plane.projectPrelaunch(replacementRequest, as: .policyReady)
        let replacementTask = Task { try await plane.run(replacementRequest) }
        await replacementAdapter.waitForLaunchCount(1)
        #expect(await plane.cleanupFailureEvidence(for: host) == nil)

        replacementTask.cancel()
        await replacementGate.open()
        await #expect(throws: CancellationError.self) {
            _ = try await replacementTask.value
        }
    }
}

extension RuntimeFreshRunCoordinatorContractTests {
    // MARK: - decision-table

    @Test
    func `decision table covers the locked precedence rows`() {
        func assertSendable(_: (some Sendable).Type) {}
        assertSendable(RuntimeControlPlane.RuntimeLease.self)
        assertSendable(RuntimeFreshRunSnapshot.self)
        assertSendable(RuntimeFreshRunSignal.self)
        assertSendable(RuntimeFreshRunDecision.self)
        assertRelaunchRows()
        assertTerminalPrecedenceRows()
        assertLaunchRows()
        assertProviderRows()
        assertReceiptEvidenceRows()
        assertDefensiveRows()
    }

    private func assertRelaunchRows() {
        let run = RuntimeRunReference("run-decision-table")
        assertRelaunchRows(for: .policyReady, allowsNone: true, run: run)
        assertRelaunchRows(for: .launchFailed, allowsNone: true, run: run)
        assertRelaunchRows(for: .policyPending, allowsNone: false, run: run)
        assertRelaunchRows(for: .launchBlocked, allowsNone: false, run: run)
        assertRelaunchRows(for: .launchCancelled, allowsNone: false, run: run)
        assertRelaunchRows(for: .launching, allowsNone: false, run: run)
        assertRelaunchRows(for: .running, allowsNone: false, run: run)
        assertRelaunchRows(for: .eventProjected, allowsNone: false, run: run)
        assertRelaunchRows(for: .eventDuplicateIgnored, allowsNone: false, run: run)
        assertRelaunchRows(for: .eventOutOfOrder, allowsNone: false, run: run)
        assertRelaunchRows(for: .completed, allowsNone: false, run: run)
        assertRelaunchRows(for: .failed, allowsNone: false, run: run)
        assertRelaunchRows(for: .interrupted, allowsNone: false, run: run)
    }

    private func assertRelaunchRows(
        for projection: RuntimeProjection,
        allowsNone: Bool,
        run: RuntimeRunReference,
    ) {
        #expect(RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            run: run,
        )) == allowsNone)
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .detachedLaunching(1),
            run: run,
        )))
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .detachedConsuming(2),
            run: run,
        )))
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .restored(3),
            run: run,
        )))
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .resuming(4),
            run: run,
        )))
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .launching(5),
            run: run,
        )))
        #expect(!RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: projection,
            lease: .consuming(6),
            run: run,
        )))
    }

    private func assertTerminalPrecedenceRows() {
        let run = RuntimeRunReference("run-decision-table")
        assertTerminalPrecedenceRows(for: .completed, run: run)
        assertTerminalPrecedenceRows(for: .failed, run: run)
        assertTerminalPrecedenceRows(for: .interrupted, run: run)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receipt(token: "receipt-late"),
            on: makeSnapshot(projection: .completed, run: run),
        ) == .persist(projection: .completed, attachReceipt: "receipt-late", lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receipt(token: "receipt-terminal"),
            on: makeSnapshot(
                projection: .completed,
                receiptToken: "receipt-terminal",
                run: run,
            ),
        ) == .ignore)
    }

    private func assertTerminalPrecedenceRows(
        for projection: RuntimeProjection,
        run: RuntimeRunReference,
    ) {
        let terminal = makeSnapshot(
            projection: projection,
            receiptToken: "receipt-terminal",
            run: run,
        )
        assertTerminalResultsAndEvents(on: terminal)
        assertTerminalAdmissionFlags(on: terminal)
        assertTerminalLifecycleSignals(on: terminal)
    }

    private func assertTerminalResultsAndEvents(
        on terminal: RuntimeFreshRunSnapshot,
    ) {
        #expect(RuntimeFreshRunDecisionTable.decide(.providerResult(.completed), on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.providerResult(.failed), on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.providerResult(.interrupted), on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .completed, hasGap: false, isDuplicate: false, isStale: false),
            on: terminal,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .failed, hasGap: false, isDuplicate: false, isStale: false),
            on: terminal,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .interrupted, hasGap: false, isDuplicate: false, isStale: false),
            on: terminal,
        ) == .ignore)
    }

    private func assertTerminalAdmissionFlags(
        on terminal: RuntimeFreshRunSnapshot,
    ) {
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .completed, hasGap: true, isDuplicate: false, isStale: false),
            on: terminal,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .failed, hasGap: false, isDuplicate: true, isStale: false),
            on: terminal,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .interrupted, hasGap: false, isDuplicate: false, isStale: true),
            on: terminal,
        ) == .ignore)
    }

    private func assertTerminalLifecycleSignals(
        on terminal: RuntimeFreshRunSnapshot,
    ) {
        #expect(RuntimeFreshRunDecisionTable.decide(.reserve, on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.callerCancel, on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.cleanupFailed, on: terminal) == .recordCleanupFailure)
        #expect(RuntimeFreshRunDecisionTable.decide(.adapterLaunchFailed, on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.orphanLaunching, on: terminal) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(.receiptPersistFailed, on: terminal) == .ignore)
    }

    private func assertLaunchRows() {
        let run = RuntimeRunReference("run-decision-table")
        let persisted = makeSnapshot(projection: .failed, receiptToken: "receipt-persisted", run: run)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .persistConflict(persisted: persisted),
            on: makeSnapshot(projection: .running, receiptToken: "receipt-local", lease: .consuming(2), run: run),
        ) == .adoptPersisted(persisted))

        let launching = makeSnapshot(projection: .launching, lease: .launching(3), run: run)
        #expect(RuntimeFreshRunDecisionTable.decide(.adapterLaunchFailed, on: launching)
            == .persist(projection: .launchFailed, attachReceipt: nil, lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(.callerCancel, on: launching)
            == .persist(projection: .launchCancelled, attachReceipt: nil, lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receipt(token: "receipt-running"),
            on: launching,
        ) == .persist(projection: .running, attachReceipt: "receipt-running", lease: .consuming(3)))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .orphanLaunching,
            on: makeSnapshot(projection: .launching, run: run),
        ) == .persist(projection: .interrupted, attachReceipt: nil, lease: .none))
    }

    private func assertProviderRows() {
        let run = RuntimeRunReference("run-decision-table")
        let running = makeSnapshot(
            projection: .running,
            receiptToken: "receipt-running",
            lease: .consuming(4),
            run: run,
        )
        assertProviderTerminalRows(on: running, run: run)
        assertCancellationRows(on: running, run: run)
    }

    private func assertProviderTerminalRows(
        on running: RuntimeFreshRunSnapshot,
        run: RuntimeRunReference,
    ) {
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receiptPersistFailed,
            on: running,
        ) == .persist(projection: .interrupted, attachReceipt: "receipt-running", lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .completed, hasGap: false, isDuplicate: false, isStale: false),
            on: running,
        ) == .persist(projection: .completed, attachReceipt: "receipt-running", lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .failed, hasGap: true, isDuplicate: false, isStale: false),
            on: running,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .failed, hasGap: false, isDuplicate: true, isStale: false),
            on: running,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerEvent(kind: .failed, hasGap: false, isDuplicate: false, isStale: true),
            on: running,
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerResult(.interrupted),
            on: running,
        ) == .persist(projection: .interrupted, attachReceipt: "receipt-running", lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerResult(.completed),
            on: makeSnapshot(projection: .running, lease: .consuming(4), run: run),
        ) == .ignore)
    }

    private func assertCancellationRows(
        on running: RuntimeFreshRunSnapshot,
        run: RuntimeRunReference,
    ) {
        #expect(RuntimeFreshRunDecisionTable.decide(
            .callerCancel,
            on: running,
        ) == .persist(
            projection: .running,
            attachReceipt: "receipt-running",
            lease: .detachedConsuming(4),
        ))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .callerCancel,
            on: makeSnapshot(
                projection: .running,
                receiptToken: "receipt-running",
                lease: .detachedConsuming(4),
                run: run,
            ),
        ) == .throwCancellation)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receiptPersistFailed,
            on: makeSnapshot(projection: .running, lease: .consuming(4), run: run),
        ) == .throwHost(.persistenceFailure))
    }

    private func assertReceiptEvidenceRows() {
        let run = RuntimeRunReference("run-receipt-evidence")
        let absentTokens: [String?] = [nil, "", "   ", "\t\n"]
        for token in absentTokens {
            let snapshot = makeSnapshot(
                projection: .running,
                receiptToken: token,
                lease: .consuming(8),
                run: run,
            )
            #expect(RuntimeFreshRunDecisionTable.decide(
                .providerResult(.completed),
                on: snapshot,
            ) == .ignore)
            #expect(RuntimeFreshRunDecisionTable.decide(
                .providerEvent(kind: .completed, hasGap: false, isDuplicate: false, isStale: false),
                on: snapshot,
            ) == .ignore)
            #expect(RuntimeFreshRunDecisionTable.decide(
                .receiptPersistFailed,
                on: snapshot,
            ) == .throwHost(.persistenceFailure))
        }

        let receiptSnapshot = makeSnapshot(
            projection: .running,
            receiptToken: "receipt-evidence",
            lease: .consuming(8),
            run: run,
        )
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerResult(.completed),
            on: receiptSnapshot,
        ) == .persist(projection: .completed, attachReceipt: "receipt-evidence", lease: .none))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receipt(token: "   "),
            on: makeSnapshot(projection: .launching, lease: .launching(8), run: run),
        ) == .throwHost(.malformedAdapterResponse))
    }

    private func assertDefensiveRows() {
        let run = RuntimeRunReference("run-defensive-rows")
        #expect(RuntimeFreshRunDecisionTable.decide(
            .reserve,
            on: makeSnapshot(projection: .policyReady, run: run),
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .reserve,
            on: makeSnapshot(projection: .running, receiptToken: "receipt", lease: .consuming(1), run: run),
        ) == .throwHost(.duplicateRunReference))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .orphanLaunching,
            on: makeSnapshot(projection: .launching, lease: .launching(1), run: run),
        ) == .throwHost(.activeRunExists))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .adapterLaunchFailed,
            on: makeSnapshot(projection: .policyReady, run: run),
        ) == .ignore)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .callerCancel,
            on: makeSnapshot(projection: .policyReady, run: run),
        ) == .throwCancellation)
        #expect(RuntimeFreshRunDecisionTable.decide(
            .receipt(token: "receipt"),
            on: makeSnapshot(projection: .policyReady, run: run),
        ) == .throwHost(.invalidEvent))
        #expect(RuntimeFreshRunDecisionTable.decide(
            .providerResult(.completed),
            on: makeSnapshot(projection: .running, lease: .consuming(1), run: run),
        ) == .ignore)
    }

    // MARK: - coordinator-contract

    /// VOY-746-coordinator_contract: a pre-receipt adapter failure is relaunchable.
    /// 접수 토큰 전 adapter 오류를 launch failure terminal로 저장하고 새 실행을 허용하는 미래 계약을 고정한다.
    /// - 검증 내용: public run 오류, durable launchFailed projection, relaunch decision.
    /// - 사전 조건: policy-ready run과 launch 실패 adapter가 구성되어 있다.
    /// - 기대 결과: `.launchFailed`가 저장되고 같은 invocation은 relaunch 가능하다.
    @Test
    func `pre-receipt adapter failure persists launchFailed`() async throws {
        let host = ExternalAgentSessionReference("host-contract-launch-failure")
        let run = RuntimeRunReference("run-contract-launch-failure")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            failsLaunch: true,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await plane.run(request)
        }
        #expect(await plane.projection(for: host) == .launchFailed)
        let stored = try #require(await plane.sessions[host]?.stored)
        #expect(RuntimeFreshRunDecisionTable.allowsRelaunch(makeSnapshot(
            projection: stored.projection,
            receiptToken: stored.providerInternalSessionReference?.rawValue,
            run: stored.runReference,
        )))
    }

    /// VOY-746-coordinator_contract: cancellation before a receipt is a launch cancellation.
    /// provider 접수 전 caller 취소를 launch cancellation terminal로 저장하고 재실행하지 않는 미래 계약을 고정한다.
    /// - 검증 내용: public run CancellationError, durable launchCancelled projection, launch count.
    /// - 사전 조건: launch gate가 열린 뒤 caller가 취소하는 policy-ready run이 있다.
    /// - 기대 결과: `.launchCancelled`가 저장되고 provider launch는 한 번만 시도된다.
    @Test
    func `pre-receipt cancel persists launchCancelled`() async throws {
        let host = ExternalAgentSessionReference("host-contract-launch-cancel")
        let run = RuntimeRunReference("run-contract-launch-cancel")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForLaunchCount(1)
        runTask.cancel()
        await launchGate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }
        #expect(await plane.projection(for: host) == .launchCancelled)
        #expect(await store.currentState()?.sessions.first?.projection == .launchCancelled)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: an orphaned launch is interrupted without provider start.
    /// receipt 없이 hydrate된 launching 상태를 compatibility flag와 무관하게 orphan으로 정리하는 미래 계약을 고정한다.
    /// - 검증 내용: public run duplicate error, durable interrupted projection, zero launch count.
    /// - 사전 조건: inactive lease와 receipt 없는 hydrated launching session이 있다.
    /// - 기대 결과: `.interrupted`가 저장되고 adapter launch는 호출되지 않는다.
    @Test
    func `orphan launching refuses relaunch without adapter start`() async throws {
        let host = ExternalAgentSessionReference("host-contract-orphan")
        let run = RuntimeRunReference("run-contract-orphan")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let orphan = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
            projection: .launching,
            providerLaunchAttempted: true,
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [orphan],
        ))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await plane.run(request)
        }
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await store.currentState()?.sessions.first?.projection == .interrupted)
        #expect(await adapter.counts().launch == 0)
    }

    /// VOY-746-coordinator_contract: receipt persistence failure never relaunches the run.
    /// provider receipt 저장 실패 뒤 같은 runReference가 두 번 시작되지 않는 미래 계약을 고정한다.
    /// - 검증 내용: persistenceFailure, receipt-bearing interrupted state, second run launch count.
    /// - 사전 조건: receipt commit save만 실패하는 policy-ready run이 있다.
    /// - 기대 결과: provider launch는 정확히 한 번이고 같은 runReference는 다시 시작되지 않는다.
    @Test
    func `receipt persist failure never relaunches`() async throws {
        let host = ExternalAgentSessionReference("host-contract-receipt-failure")
        let run = RuntimeRunReference("run-contract-receipt-failure")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await plane.run(request)
        }
        let stored = try #require(await store.currentState()?.sessions.first)
        #expect(stored.projection == .interrupted)
        #expect(stored.providerInternalSessionReference?.rawValue == "opaque-1")
        #expect(await adapter.counts().launch == 1)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await plane.run(request)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: a receipt CAS conflict adopts a persisted terminal without relaunch.
    /// receipt CAS conflict 뒤 durable terminal을 채택하고 provider를 재시작하지 않는지 검증한다.
    /// - 검증 내용: receipt binding 병합, terminal 결과, exact apply/update와 launch count.
    /// - 사전 조건: receipt apply conflict가 같은 run의 persisted completed terminal을 설치한다.
    /// - 기대 결과: 한 번의 bounded repair apply 뒤 completed가 반환되고 launch는 한 번이다.
    @Test
    func `cas conflict adopts persisted terminal without a second launch`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-receipt-cas"
        let run = RuntimeRunReference("run-contract-receipt-cas")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let terminal = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
            projection: .completed,
            providerLaunchAttempted: true,
        )
        let terminalState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [terminal],
        )
        let store = DeterministicHostMutationRuntimeStateStore(
            conflictingUpdateStates: [3: terminalState],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        try await plane.projectPrelaunch(request, as: .policyReady)

        #expect(try await plane.run(request).outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.stored.providerInternalSessionReference
            == ProviderInternalSessionReference("opaque-1"))
        #expect(await store.updateCount == 4)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: cancellation after receipt remains detached consumption.
    /// receipt commit 이후 consume 중 취소가 CancellationError로 끝나고 실패 terminal을 만들지 않는 미래 계약을 고정한다.
    /// - 검증 내용: public run CancellationError, running projection, detached consuming lease.
    /// - 사전 조건: terminal-only adapter 결과가 gate에서 대기하는 receipt-bearing run이 있다.
    /// - 기대 결과: `.failed`/`.launchFailed`가 아닌 상태와 detached consuming lease가 남는다.
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
        let session = try #require(await plane.sessions[host])
        #expect(session.stored.projection == .running)
        #expect(session.stored.projection != .failed)
        #expect(session.stored.projection != .launchFailed)
        #expect(isDetachedConsuming(session.lease))
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: detached consumption accepts a later contiguous provider terminal.
    /// receipt 이후 caller 취소로 detached consuming이 된 run이 후속 provider terminal을 수용하는지 검증한다.
    /// - 검증 내용: callerCancel decision, detached lease, contiguous provider terminal, exact apply/launch count.
    /// - 사전 조건: receipt-bearing provider stream이 gate에서 대기하고 caller cancellation이 먼저 선형화된다.
    /// - 기대 결과: 취소 호출은 CancellationError이고 후속 completed event는 한 번의 apply로 terminalize된다.
    @Test
    func `detached cancellation accepts later contiguous provider terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-detached-terminal"
        let run = RuntimeRunReference("run-contract-detached-terminal")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        runTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }
        #expect(await plane.sessions[host]?.lease == .detachedConsuming(2))
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.applyCount == 4)

        let terminal = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "detached-completed",
            kind: .completed,
        )
        #expect(try await plane.accept(
            terminal,
            host: host,
            expectedSource: .provider,
        )?.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(await store.applyCount == 5)
        #expect(await adapter.counts().launch == 1)

        await streamGate.open()
    }

    /// VOY-746-coordinator_contract: stale cancellation cannot mutate a replacement run.
    /// 이전 run의 지연된 cancellation transition이 같은 host의 후속 run에 적용되지 않는지 검증한다.
    /// - 검증 내용: replacement run reference, launching projection과 lease, provider launch count.
    /// - 사전 조건: 이전 run과 다른 reference를 가진 replacement가 provider launch에서 대기한다.
    /// - 기대 결과: stale cancellation은 no-op이고 replacement는 정상 완료한다.
    @Test
    func `stale cancellation cannot mutate a replacement run`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-stale-cancel"
        let staleRun = RuntimeRunReference("run-contract-stale-cancel-old")
        let replacementRun = RuntimeRunReference("run-contract-stale-cancel-replacement")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: replacementRun, adapterID: "terminal")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let replacementTask = Task { try await plane.run(request) }
        await adapter.waitForLaunchCount(1)
        let snapshot = try await plane.mutateAfterPersistedTransitions { plane in
            var registry = plane.sessions
            try plane.persistCallerCancellationTransition(
                host: host,
                originatingRunReference: staleRun,
                in: &registry,
            )
            return registry[host]?.freshRunSnapshot()
        }

        #expect(snapshot?.runReference == replacementRun)
        #expect(snapshot?.runReference != staleRun)
        #expect(snapshot?.projection == .launching)
        #expect(snapshot?.lease == .launching(2))
        #expect(await adapter.counts().launch == 1)

        await launchGate.open()
        #expect(try await replacementTask.value.outcome == .completed)
    }

    /// VOY-746-coordinator_contract: a persisted host terminal wins a late provider finish.
    /// provider finish 결과가 늦게 도착해도 먼저 저장된 host terminal을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: host interrupted terminal, provider finish 이후 public 결과와 durable projection.
    /// - 사전 조건: terminal-only provider 결과가 gate에서 대기하고 host terminal이 먼저 저장된다.
    /// - 기대 결과: provider finish 이후에도 interrupted 결과와 projection이 유지된다.
    @Test
    func `persisted host terminal wins late provider finish`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-late-finish"
        let run = RuntimeRunReference("run-contract-late-finish")
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

        #expect(try await plane.ingestHostEvent(makeHostTerminalEvent(
            host: host,
            run: run,
            kind: .interrupted,
        ))?.outcome == .interrupted)
        await resultGate.open()

        #expect(try await runTask.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await store.currentState()?.sessions.first?.projection == .interrupted)
    }

    /// VOY-746-coordinator_contract: a terminal event CAS conflict uses one bounded repair.
    /// provider terminal event의 첫 CAS conflict 이후 재적용은 한 번만 수행되는지 검증한다.
    /// - 검증 내용: completed 결과, terminal projection, exact apply/launch count.
    /// - 사전 조건: provider completed event와 event commit conflict가 구성되어 있다.
    /// - 기대 결과: read-repair 뒤 한 번의 repair apply로 completed가 저장되고 provider는 재실행되지 않는다.
    @Test
    func `terminal event CAS conflict uses one bounded repair`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-terminal-cas"
        let run = RuntimeRunReference("run-contract-terminal-cas")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-cas",
                kind: .completed,
            )]],
        )
        let store = InMemoryRuntimeStateStore(conflictingSaveNumbers: [4])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        try await plane.projectPrelaunch(
            makeLaunch(host: host, run: run, adapterID: "sdk"),
            as: .policyReady,
        )

        #expect(try await plane.run(makeLaunch(host: host, run: run, adapterID: "sdk")).outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await store.applyCount == 5)
        #expect(await adapter.counts().launch == 1)
    }

    /// VOY-746-coordinator_contract: a second terminal-event CAS conflict preserves contention classification.
    /// provider terminal event의 유일한 repair write도 conflict하면 오류 분류와 write 상한을 유지하는지 검증한다.
    /// - 검증 내용: public persistenceConflict, exact apply count와 provider launch count.
    /// - 사전 조건: terminal event의 최초 저장과 유일한 repair 저장이 모두 CAS conflict한다.
    /// - 기대 결과: persistenceConflict가 전달되고 apply는 총 5회, provider launch는 1회이며 consumption claim은 해제된다.
    @Test
    func `terminal event second CAS conflict remains persistenceConflict`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-terminal-event-second-cas"
        let run = RuntimeRunReference("run-contract-terminal-event-second-cas")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-event-second-cas",
                kind: .completed,
            )]],
        )
        let store = InMemoryRuntimeStateStore(conflictingSaveNumbers: [4, 5])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceConflict) {
            _ = try await plane.run(request)
        }
        #expect(await store.applyCount == 5)
        #expect(await adapter.counts().launch == 1)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
        #expect(await plane.sessions[host]?.lease.isActive == false)
    }

    /// VOY-746-coordinator_contract: a second terminal-result CAS conflict preserves contention classification.
    /// 허용된 한 번의 repair write도 conflict하면 추가 재시도 없이 persistenceConflict를 전달하는 계약을 고정한다.
    /// - 검증 내용: public 오류, exact apply count, provider launch count와 durable projection.
    /// - 사전 조건: terminal result의 최초 저장과 유일한 repair 저장이 모두 CAS conflict한다.
    /// - 기대 결과: persistenceConflict가 전달되고 apply는 총 5회, provider launch는 1회다.
    @Test
    func `terminal result second CAS conflict remains persistenceConflict`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-terminal-second-cas"
        let run = RuntimeRunReference("run-contract-terminal-second-cas")
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let store = InMemoryRuntimeStateStore(conflictingSaveNumbers: [4, 5])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "terminal")
        try await plane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceConflict) {
            _ = try await plane.run(request)
        }
        #expect(await store.applyCount == 5)
        #expect(await adapter.counts().launch == 1)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
    }

    /// VOY-746-coordinator_contract: a provider sequence gap does not synthesize a terminal.
    /// gapped terminal event가 provider result fallback으로 terminal projection을 만들지 않는지 검증한다.
    /// - 검증 내용: public run 오류, eventOutOfOrder projection, gap evidence와 sequence cursor.
    /// - 사전 조건: sequence 2의 completed provider event만 전달되는 stream이 있다.
    /// - 기대 결과: run은 invalidEvent로 끝나고 durable session은 terminal이 아닌 out-of-order 상태이며 claim은 해제된다.
    @Test
    func `sequence gap does not synthesize terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-gap"
        let run = RuntimeRunReference("run-contract-gap")
        let event = makeEvent(
            host: host,
            run: run,
            sequence: 2,
            idempotencyKey: "gap-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[event]],
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        await #expect(throws: RuntimeHostError.invalidEvent) {
            _ = try await runTask.value
        }

        let stored = try #require(await store.currentState()?.sessions.first)
        #expect(stored.projection == .eventOutOfOrder)
        #expect(stored.lastSequence == 2)
        #expect(stored.eventEvidence.contains {
            if case let .sequenceGap(expected, received) = $0 {
                return expected == 1 && received == 2
            }
            return false
        })
        #expect(await plane.sessions[host]?.lease.isActive == false)
    }

    /// VOY-746-coordinator_contract: a duplicate provider event is ignored.
    /// 중복 terminal frame이 cursor와 projection을 다시 변경하지 않는지 검증한다.
    /// - 검증 내용: public run 오류, duplicate evidence, accepted/processed counts와 nonterminal projection.
    /// - 사전 조건: progress frame과 같은 idempotency key의 completed duplicate frame이 전달된다.
    /// - 기대 결과: duplicate는 무시되고 accepted count는 1, processed count는 2로 남는다.
    @Test
    func `duplicate event is ignored`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-duplicate-event"
        let run = RuntimeRunReference("run-contract-duplicate-event")
        let progress = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "same-event",
            kind: .progress,
        )
        let duplicate = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "same-event",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[progress, duplicate]],
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        await #expect(throws: RuntimeHostError.invalidEvent) {
            _ = try await runTask.value
        }

        let stored = try #require(await store.currentState()?.sessions.first)
        #expect(stored.projection == .eventProjected)
        #expect(stored.acceptedEventCount == 1)
        #expect(stored.processedEventCount == 2)
        #expect(stored.acceptedIdempotencyKeys == [RuntimeIdempotencyKey("same-event")])
        #expect(stored.eventEvidence.contains {
            if case let .ignoredDuplicate(key) = $0 { return key == RuntimeIdempotencyKey("same-event") }
            return false
        })
    }

    /// VOY-746-coordinator_contract: contiguous provider completion persists completed.
    /// contiguous provider event가 sequence와 idempotency evidence를 보존하며 completed를 저장하는지 검증한다.
    /// - 검증 내용: public run 결과, durable terminal projection, cursor/count/key persistence.
    /// - 사전 조건: sequence 1 progress와 sequence 2 completed provider event가 전달된다.
    /// - 기대 결과: completed가 저장되고 두 event의 sequence/count/key가 durable state에 남는다.
    @Test
    func `contiguous provider completed persists completed`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-contiguous-completed"
        let run = RuntimeRunReference("run-contract-contiguous-completed")
        let progress = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "progress-1",
            kind: .progress,
        )
        let completed = makeEvent(
            host: host,
            run: run,
            sequence: 2,
            idempotencyKey: "completed-2",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[progress, completed]],
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        #expect(try await plane.run(request).outcome == .completed)
        let stored = try #require(await store.currentState()?.sessions.first)
        #expect(stored.projection == .completed)
        #expect(stored.lastSequence == 2)
        #expect(stored.acceptedEventCount == 2)
        #expect(stored.processedEventCount == 2)
        #expect(stored.acceptedIdempotencyKeys == [
            RuntimeIdempotencyKey("progress-1"),
            RuntimeIdempotencyKey("completed-2"),
        ])
        #expect(stored.eventEvidence.isEmpty)
    }

    private func makeSnapshot(
        projection: RuntimeProjection,
        receiptToken: String? = nil,
        lease: RuntimeControlPlane.RuntimeLease = .none,
        run: RuntimeRunReference = RuntimeRunReference("run-fixture"),
    ) -> RuntimeFreshRunSnapshot {
        RuntimeFreshRunSnapshot(
            projection: projection,
            receiptToken: receiptToken,
            lease: lease,
            runReference: run,
        )
    }

    private func isDetachedConsuming(_ lease: RuntimeControlPlane.RuntimeLease) -> Bool {
        if case .detachedConsuming = lease { return true }
        return false
    }

    private func makeHostTerminalEvent(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        kind: RuntimeEventKind = .completed,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-terminal"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-terminal"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: kind,
        )
    }
}

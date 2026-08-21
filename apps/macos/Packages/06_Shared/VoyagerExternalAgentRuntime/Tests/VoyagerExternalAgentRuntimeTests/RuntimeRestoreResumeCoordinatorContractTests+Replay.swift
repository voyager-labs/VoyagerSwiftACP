import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-resume_replay

    // MARK: - VOY-747-resume_expiry_result_race

    /// VOY-747-resume_expiry_result_race: provider result at exact claim expiry clears owned claim before conflict.
    /// provider result가 injected clock의 정확한 60초 만료 경계에 도착해도 첫 conflict가 만료 claim을 회수하는지 검증한다.
    /// - 검증 내용: persistenceConflict 분류, 만료 claim과 local lease의 원자적 정리, 동일 run/receipt, 재시도 provider 호출 횟수.
    /// - 사전 조건: terminal-only provider result가 gate에서 대기하고 restored resume claim을 60초 전진시킨다.
    /// - 기대 결과: 첫 resume은 persistenceConflict를 반환하지만 즉시 같은 plane의 restore/resume이 동일 receipt로 완료된다.
    @Test
    func `provider result at exact claim expiry clears owned claim before conflict`() async throws {
        let fixture = makeProviderResultExpiryFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let restored = try #require(await fixture.store.currentState()?.sessions.first)
        let restoredClaim = try #require(restored.restorationClaim)
        let ownerToken = await fixture.plane.restorationOwnerToken
        #expect(restoredClaim.ownerToken == ownerToken)

        let firstResume = Task { try await fixture.plane.resumeRestoredRun(hostReference: fixture.host) }
        await fixture.adapter.waitForTerminalResultCount(1)
        await fixture.clock.waitUntilSleeping()
        fixture.clock.advance(by: 60)
        await fixture.resultGate.open()
        await #expect(throws: RuntimeHostError.persistenceConflict) { _ = try await firstResume.value }

        try await expectProviderResultExpiryConflict(fixture)
        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let retryResult = try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        try await expectProviderResultExpiryCompletion(fixture, result: retryResult)
    }

    /// VOY-747-restored_stream_reuses_receipt_and_completes_once: restored stream reuses receipt and completes once.
    /// 복원된 stream 경로가 저장된 실행 receipt를 재사용하고 terminal 경계를 한 번만 통과하는지 검증한다.
    /// - 검증 내용: 동일 run/receipt, eventStream 1회, terminalResult 1회, accepted event와 terminal projection.
    /// - 사전 조건: provider receipt를 가진 running snapshot과 completed stream event가 구성되어 있다.
    /// - 기대 결과: 결과와 저장 projection이 completed로 수렴하고 claim이 제거된다.
    @Test
    func `restored stream reuses receipt and completes once`() async throws {
        let host: ExternalAgentSessionReference = "replay-stream-host"
        let run = RuntimeRunReference("replay-stream-run")
        let receiptReference = ProviderInternalSessionReference("replay-stream-receipt")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: receiptReference,
            runReference: run,
            projection: .running,
        )
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://replay-stream"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [
                [
                    makeEvent(
                        host: host,
                        run: run,
                        sequence: 1,
                        idempotencyKey: "replay-stream-terminal",
                        kind: .completed,
                    ),
                ],
            ],
            terminalResultOverride: expected,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let result = try await plane.resumeRestoredRun(hostReference: host)
        let persisted = try #require(await store.currentState()?.sessions.first)
        let binding = try #require(await adapter.receivedRestartBindings().first)

        expectRestoredReceipt(
            result: result,
            expected: expected,
            persisted: persisted,
            binding: binding,
            receiptReference: receiptReference,
        )
        expectCompletedSession(persisted)
        #expect(await plane.acceptedEventCount(for: host) == 1)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-process_restart_after_claim_recovery: process restart resumes same run after claim recovery.
    /// provider process interruption 뒤 새 control plane이 만료된 claim을 새로 획득하고 동일 receipt로 재개하는지 검증한다.
    /// - 검증 내용: 첫 stream interruption, new owner claim, 동일 run/receipt, provider 재호출 비동시성.
    /// - 사전 조건: 첫 adapter는 processExit를 반환하고 replacement adapter는 completed event를 반환한다.
    /// - 기대 결과: 첫 결과는 retryable claim으로 끝나고 새 plane만 completed terminal을 저장한다.
    @Test
    func `process restart resumes same run after claim recovery`() async throws {
        let fixture = makeProcessRestartFixture()
        try await fixture.firstPlane.register(fixture.firstAdapter)

        #expect(try await fixture.firstPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        await #expect(throws: RuntimeHostError.adapterFailure(
            .processExit,
            RuntimeDiagnosticCode("process_exit"),
        )) {
            _ = try await fixture.firstPlane.resumeRestoredRun(hostReference: fixture.host)
        }
        #expect(await fixture.firstPlane.sessions[fixture.host]?.lease.isAwaitingResumption == true)
        #expect(await fixture.firstAdapter.counts().stream == 1)
        #expect(await fixture.firstAdapter.counts().terminalResult == 0)
        let firstPersisted = try #require(await fixture.store.currentState()?.sessions.first)
        let firstOwnerToken = await fixture.firstPlane.restorationOwnerToken
        expectRetryClaim(
            firstPersisted,
            fixture: fixture,
            ownerToken: firstOwnerToken,
        )

        try await fixture.replacementPlane.register(fixture.replacementAdapter)
        #expect(try await fixture.replacementPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let result = try await fixture.replacementPlane.resumeRestoredRun(hostReference: fixture.host)
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        let binding = try #require(await fixture.replacementAdapter.receivedRestartBindings().first)

        expectRestoredReceipt(
            result: result,
            expected: fixture.replacementResult,
            persisted: persisted,
            binding: binding,
            receiptReference: fixture.receiptReference,
        )
        expectCompletedSession(persisted)
        #expect(await fixture.firstAdapter.counts().stream == 1)
        #expect(await fixture.replacementAdapter.counts().stream == 1)
        #expect(await fixture.replacementAdapter.counts().terminalResult == 1)
    }

    /// VOY-747-transport_loss_after_claim_recovery: transport loss resumes the same run after claim recovery.
    /// restored provider transport loss가 process exit와 동일하게 retry claim을 보존하고 새 claimant의 재개를 허용하는지 검증한다.
    /// - 검증 내용: 첫 owner의 transportLoss, 동일 persisted run/receipt와 retry claim, bounded provider calls, replacement
    /// completion.
    /// - 사전 조건: 첫 deterministic adapter는 transport loss를 반환하고 replacement adapter는 같은 run의 completed event를 반환한다.
    /// - 기대 결과: 첫 owner는 retryable interruption을 표면화하고, 만료 후 새 claimant만 동일 receipt로 재개해 완료한다.
    @Test
    func `transport loss resumes same run after claim recovery`() async throws {
        let fixture = makeProcessRestartFixture(
            failureKind: .transportLoss,
            diagnosticCode: "transport_loss",
        )
        try await fixture.firstPlane.register(fixture.firstAdapter)

        #expect(try await fixture.firstPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        await #expect(throws: RuntimeHostError.adapterFailure(
            .transportLoss,
            RuntimeDiagnosticCode("transport_loss"),
        )) {
            _ = try await fixture.firstPlane.resumeRestoredRun(hostReference: fixture.host)
        }
        #expect(await fixture.firstPlane.sessions[fixture.host]?.lease.isAwaitingResumption == true)
        #expect(await fixture.firstAdapter.counts().stream == 1)
        #expect(await fixture.firstAdapter.counts().terminalResult == 0)
        let firstPersisted = try #require(await fixture.store.currentState()?.sessions.first)
        let firstOwnerToken = await fixture.firstPlane.restorationOwnerToken
        expectRetryClaim(
            firstPersisted,
            fixture: fixture,
            ownerToken: firstOwnerToken,
        )

        try await fixture.replacementPlane.register(fixture.replacementAdapter)
        #expect(try await fixture.replacementPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let result = try await fixture.replacementPlane.resumeRestoredRun(hostReference: fixture.host)
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        let binding = try #require(await fixture.replacementAdapter.receivedRestartBindings().first)

        expectRestoredReceipt(
            result: result,
            expected: fixture.replacementResult,
            persisted: persisted,
            binding: binding,
            receiptReference: fixture.receiptReference,
        )
        expectCompletedSession(persisted)
        #expect(await fixture.firstAdapter.counts().stream == 1)
        #expect(await fixture.replacementAdapter.counts().stream == 1)
        #expect(await fixture.replacementAdapter.counts().terminalResult == 1)
    }

    /// VOY-747-duplicate_restored_terminal: duplicate restored terminal mutates once.
    /// terminal replay가 이미 완료된 restored projection을 다시 저장하거나 accepted count를 증가시키지 않는지 검증한다.
    /// - 검증 내용: 첫 terminal 저장 이후 duplicate provider frame의 실패와 mutation/accepted count 불변성.
    /// - 사전 조건: completed provider frame으로 restore/resume이 완료되어 있다.
    /// - 기대 결과: duplicate frame은 terminal replay로 거부되고 저장 terminal은 한 번만 유지된다.
    @Test
    func `duplicate restored terminal mutates once`() async throws {
        let host: ExternalAgentSessionReference = "replay-duplicate-terminal-host"
        let run = RuntimeRunReference("replay-duplicate-terminal-run")
        let context = makeContext()
        let terminal = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "replay-duplicate-terminal",
            kind: .completed,
        )
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            eventsByLaunch: [[terminal]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        _ = try await plane.resumeRestoredRun(hostReference: host)
        let applyCount = await store.applyCount
        let acceptedCount = await plane.acceptedEventCount(for: host)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await plane.accept(terminal, host: host, expectedSource: .provider)
        }

        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(await store.applyCount == applyCount)
        #expect(await plane.acceptedEventCount(for: host) == acceptedCount)
        #expect(await plane.projection(for: host) == .completed)
        #expect(persisted.projection == .completed)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-stale_restored_frame: stale restored frame cannot move projection backward.
    /// restored provider cursor가 stale frame을 evidence로만 남기고 terminal projection을 뒤로 이동시키지 않는지 검증한다.
    /// - 검증 내용: stale evidence, accepted count, sequence cursor, completed terminal과 provider 호출 횟수.
    /// - 사전 조건: progress 1, stale 0, completed 2 순서의 restored stream이 구성되어 있다.
    /// - 기대 결과: stale frame은 accepted count에 포함되지 않고 최종 projection은 completed다.
    @Test
    func `stale restored frame cannot move projection backward`() async throws {
        let host: ExternalAgentSessionReference = "replay-stale-frame-host"
        let run = RuntimeRunReference("replay-stale-frame-run")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            runReference: run,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            eventsByLaunch: [
                [
                    makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "replay-progress", kind: .progress),
                    makeEvent(host: host, run: run, sequence: 0, idempotencyKey: "replay-stale", kind: .progress),
                    makeEvent(host: host, run: run, sequence: 2, idempotencyKey: "replay-completed", kind: .completed),
                ],
            ],
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        _ = try await plane.resumeRestoredRun(hostReference: host)
        let persisted = try #require(await store.currentState()?.sessions.first)

        #expect(await plane.projection(for: host) == .completed)
        #expect(persisted.projection == .completed)
        #expect(persisted.lastSequence == 2)
        #expect(await plane.acceptedEventCount(for: host) == 2)
        #expect(await plane.eventEvidence(for: host) == [
            .staleSequence(lastAccepted: 1, received: 0),
        ])
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-restored_sequence_gap: restored sequence gap preserves retry claim.
    /// sequence gap terminal replay가 invalidEvent로 끝나도 running projection과 restoration claim을 보존하는지 검증한다.
    /// - 검증 내용: gap evidence, invalidEvent, nonterminal projection, retry lease/claim, provider call counts.
    /// - 사전 조건: cursor 0에서 sequence 2 completed frame과 terminalResult 미지원 adapter가 구성되어 있다.
    /// - 기대 결과: terminalize하지 않고 동일 run의 retry claim을 보존한다.
    @Test
    func `restored sequence gap preserves retry claim`() async throws {
        let host: ExternalAgentSessionReference = "replay-gap-host"
        let run = RuntimeRunReference("replay-gap-run")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: makeRestoreStreamOnlyCapabilities(),
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: makeRestoreStreamOnlyCapabilities(),
            eventsByLaunch: [
                [
                    makeEvent(
                        host: host,
                        run: run,
                        sequence: 2,
                        idempotencyKey: "replay-gap-terminal",
                        kind: .completed,
                    ),
                ],
            ],
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let ownerToken = await plane.restorationOwnerToken
        await #expect(throws: RuntimeHostError.invalidEvent) {
            _ = try await plane.resumeRestoredRun(hostReference: host)
        }
        let persisted = try #require(await store.currentState()?.sessions.first)

        #expect(await plane.projection(for: host) == .eventOutOfOrder)
        #expect(persisted.projection == .eventOutOfOrder)
        #expect(persisted.eventEvidence == [.sequenceGap(expected: 1, received: 2)])
        #expect(persisted.restorationClaim?.ownerToken == ownerToken)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await plane.acceptedEventCount(for: host) == 1)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-old_owner_replacement_takeover: old owner result cannot commit after replacement takeover.
    /// replacement claim이 인수된 뒤 이전 owner의 terminal result가 durable state를 바꾸지 못하는지 검증한다.
    /// - 검증 내용: old terminalResult gate, replacement claim identity, persistenceConflict, terminal/receipt 불변성.
    /// - 사전 조건: terminal-only old owner가 result 경계에서 대기하고 replacement owner가 만료 후 claim을 획득한다.
    /// - 기대 결과: old result는 commit되지 않고 replacement running claim과 동일 receipt가 유지된다.
    @Test
    func `old owner result cannot commit after replacement takeover`() async throws {
        let fixture = makeReplacementTakeoverFixture()
        try await fixture.oldPlane.register(fixture.oldAdapter)
        try await fixture.replacementPlane.register(fixture.replacementAdapter)

        #expect(try await fixture.oldPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let oldResume = Task { try await fixture.oldPlane.resumeRestoredRun(hostReference: fixture.host) }
        await fixture.oldAdapter.waitForTerminalResultCount(1)

        #expect(try await fixture.replacementPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let replacementOwner = await fixture.replacementPlane.restorationOwnerToken
        await fixture.terminalGate.open()
        await #expect(throws: RuntimeHostError.persistenceConflict) {
            _ = try await oldResume.value
        }

        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        #expect(persisted.runReference == fixture.run)
        #expect(persisted.providerInternalSessionReference == fixture.receiptReference)
        #expect(persisted.projection == .running)
        #expect(persisted.restorationClaim?.ownerToken == replacementOwner)
        #expect(await fixture.oldAdapter.counts().terminalResult == 1)
        await expectUnusedAdapter(fixture.replacementAdapter.counts())
    }
}

private struct ProviderResultExpiryFixture {
    let clock: DeterministicRuntimeRestorationClock
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let receiptReference: ProviderInternalSessionReference
    let context: RuntimeContextPolicy
    let expected: RuntimeResult
    let resultGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

private func makeProviderResultExpiryFixture() -> ProviderResultExpiryFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host = ExternalAgentSessionReference("replay-expiry-result-host")
    let run = RuntimeRunReference("replay-expiry-result-run")
    let receiptReference = ProviderInternalSessionReference("replay-expiry-result-receipt")
    let context = makeContext()
    let expected = RuntimeResult(
        runReference: run,
        outcome: .completed,
        artifactReferences: ["artifact://replay-expiry-result"],
    )
    let resultGate = RuntimeTestGate()
    let capabilities = makeRestoreTerminalOnlyCapabilities()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: receiptReference,
        runReference: run,
        capabilitySnapshot: capabilities,
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        capabilities: capabilities,
        eventsByLaunch: [[]],
        terminalResultOverride: expected,
        terminalResultGate: resultGate,
    )
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    return ProviderResultExpiryFixture(
        clock: clock,
        host: host,
        run: run,
        receiptReference: receiptReference,
        context: context,
        expected: expected,
        resultGate: resultGate,
        store: store,
        adapter: adapter,
        plane: plane,
    )
}

private func expectProviderResultExpiryConflict(
    _ fixture: ProviderResultExpiryFixture,
) async throws {
    let afterConflict = try #require(await fixture.store.currentState()?.sessions.first)
    #expect(afterConflict.runReference == fixture.run)
    #expect(afterConflict.providerInternalSessionReference == fixture.receiptReference)
    #expect(afterConflict.restorationClaim == nil)
    #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
    #expect(await fixture.plane.sessions[fixture.host]?.stored.runReference == fixture.run)
    #expect(await fixture.plane.sessions[fixture.host]?.stored.restorationClaim == nil)
}

private func expectProviderResultExpiryCompletion(
    _ fixture: ProviderResultExpiryFixture,
    result: RuntimeResult,
) async throws {
    let completed = try #require(await fixture.store.currentState()?.sessions.first)
    #expect(result == fixture.expected)
    #expect(completed.runReference == fixture.run)
    #expect(completed.providerInternalSessionReference == fixture.receiptReference)
    #expect(completed.restorationClaim == nil)
    #expect(completed.projection == .completed)
    #expect(await fixture.adapter.receivedRestartBindings().count == 2)
    #expect(await fixture.adapter.receivedRestartBindings().allSatisfy {
        $0.runReference == fixture.run && $0.providerInternalSessionReference == fixture.receiptReference
    })
    #expect(await fixture.adapter.counts().stream == 0)
    #expect(await fixture.adapter.counts().terminalResult == 2)
    #expect(await fixture.store.applyCount == 6)
}

private struct ReplacementTakeoverFixture {
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let receiptReference: ProviderInternalSessionReference
    let context: RuntimeContextPolicy
    let store: InMemoryRuntimeStateStore
    let oldPlane: RuntimeControlPlane
    let replacementPlane: RuntimeControlPlane
    let oldAdapter: DeterministicRuntimeAdapter
    let replacementAdapter: DeterministicRuntimeAdapter
    let terminalGate: RuntimeTestGate
}

private struct ReplacementTakeoverAdapters {
    let old: DeterministicRuntimeAdapter
    let replacement: DeterministicRuntimeAdapter
}

private func makeReplacementTakeoverFixture() -> ReplacementTakeoverFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let oldClock = DeterministicRuntimeRestorationClock(currentDate: now)
    let replacementClock = DeterministicRuntimeRestorationClock(currentDate: now.addingTimeInterval(61))
    let host: ExternalAgentSessionReference = "replay-replacement-host"
    let run = RuntimeRunReference("replay-replacement-run")
    let receiptReference = ProviderInternalSessionReference("replay-replacement-receipt")
    let context = makeContext()
    let capabilities = makeRestoreTerminalOnlyCapabilities()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: receiptReference,
        runReference: run,
        capabilitySnapshot: capabilities,
        projection: .running,
    )
    let terminalGate = RuntimeTestGate()
    let adapters = makeReplacementTakeoverAdapters(
        run: run,
        capabilities: capabilities,
        terminalGate: terminalGate,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let oldPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: oldClock.runtimeClock,
    )
    let replacementPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: replacementClock.runtimeClock,
    )
    return ReplacementTakeoverFixture(
        host: host,
        run: run,
        receiptReference: receiptReference,
        context: context,
        store: store,
        oldPlane: oldPlane,
        replacementPlane: replacementPlane,
        oldAdapter: adapters.old,
        replacementAdapter: adapters.replacement,
        terminalGate: terminalGate,
    )
}

private func makeReplacementTakeoverAdapters(
    run: RuntimeRunReference,
    capabilities: RuntimeCapabilities,
    terminalGate: RuntimeTestGate,
) -> ReplacementTakeoverAdapters {
    let old = DeterministicRuntimeAdapter(
        id: "sdk",
        capabilities: capabilities,
        terminalResultOverride: RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://old-owner"],
        ),
        terminalResultGate: terminalGate,
    )
    return ReplacementTakeoverAdapters(
        old: old,
        replacement: DeterministicRuntimeAdapter(id: "sdk", capabilities: capabilities),
    )
}

private struct ProcessRestartFixture {
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let receiptReference: ProviderInternalSessionReference
    let context: RuntimeContextPolicy
    let replacementResult: RuntimeResult
    let store: InMemoryRuntimeStateStore
    let firstPlane: RuntimeControlPlane
    let replacementPlane: RuntimeControlPlane
    let firstAdapter: DeterministicRuntimeAdapter
    let replacementAdapter: DeterministicRuntimeAdapter
}

private struct ProcessRestartAdapters {
    let first: DeterministicRuntimeAdapter
    let replacement: DeterministicRuntimeAdapter
    let result: RuntimeResult
}

private func makeProcessRestartFixture(
    failureKind: RuntimeAdapterFailureKind = .processExit,
    diagnosticCode: String = "process_exit",
) -> ProcessRestartFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let firstClock = DeterministicRuntimeRestorationClock(currentDate: now)
    let replacementClock = DeterministicRuntimeRestorationClock(currentDate: now.addingTimeInterval(61))
    let host: ExternalAgentSessionReference = "process-restart-host"
    let run = RuntimeRunReference("process-restart-run")
    let receiptReference = ProviderInternalSessionReference("process-restart-receipt")
    let context = makeContext()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: receiptReference,
        runReference: run,
        projection: .running,
    )
    let adapters = makeProcessRestartAdapters(
        host: host,
        run: run,
        failureKind: failureKind,
        diagnosticCode: diagnosticCode,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let firstPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: firstClock.runtimeClock,
    )
    let replacementPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: replacementClock.runtimeClock,
    )
    return ProcessRestartFixture(
        host: host,
        run: run,
        receiptReference: receiptReference,
        context: context,
        replacementResult: adapters.result,
        store: store,
        firstPlane: firstPlane,
        replacementPlane: replacementPlane,
        firstAdapter: adapters.first,
        replacementAdapter: adapters.replacement,
    )
}

private func makeProcessRestartAdapters(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    failureKind: RuntimeAdapterFailureKind,
    diagnosticCode: String,
) -> ProcessRestartAdapters {
    let first = DeterministicRuntimeAdapter(
        id: "sdk",
        eventStreamRuntimeFailure: RuntimeAdapterFailure(
            kind: failureKind,
            diagnosticCode: RuntimeDiagnosticCode(diagnosticCode),
        ),
    )
    let result = RuntimeResult(
        runReference: run,
        outcome: .completed,
        artifactReferences: ["artifact://process-restart"],
    )
    let replacement = DeterministicRuntimeAdapter(
        id: "sdk",
        eventsByLaunch: [
            [
                makeEvent(
                    host: host,
                    run: run,
                    sequence: 1,
                    idempotencyKey: "process-restart-terminal",
                    kind: .completed,
                ),
            ],
        ],
        terminalResultOverride: result,
    )
    return ProcessRestartAdapters(first: first, replacement: replacement, result: result)
}

private func makeRestoreStreamOnlyCapabilities() -> RuntimeCapabilities {
    RuntimeCapabilities(
        discovery: .supported,
        eventStream: .supported,
        approval: .unsupported,
        cancellation: .unsupported,
        queuedInput: .unsupported,
        terminalResult: .unsupported,
        timeout: .supported,
        sameIdentityResume: .supported,
        reconstruction: .supported,
        explicitArtifact: .supported,
        workingDirectory: .supported,
        additionalRoots: .supported,
        authStatusProbe: .supported,
    )
}

private func makeRestoreTerminalOnlyCapabilities() -> RuntimeCapabilities {
    RuntimeCapabilities(
        discovery: .supported,
        eventStream: .unsupported,
        approval: .unsupported,
        cancellation: .unsupported,
        queuedInput: .unsupported,
        terminalResult: .supported,
        timeout: .supported,
        sameIdentityResume: .supported,
        reconstruction: .supported,
        explicitArtifact: .supported,
        workingDirectory: .supported,
        additionalRoots: .supported,
        authStatusProbe: .supported,
    )
}

private func expectRestoredReceipt(
    result: RuntimeResult,
    expected: RuntimeResult,
    persisted: RuntimeStoredSession,
    binding: RuntimeRestartBinding,
    receiptReference: ProviderInternalSessionReference,
) {
    let run = expected.runReference
    #expect(result == expected)
    #expect(result.runReference == run)
    #expect(persisted.runReference == run)
    #expect(persisted.providerInternalSessionReference == receiptReference)
    #expect(binding.runReference == run)
    #expect(binding.providerInternalSessionReference == receiptReference)
}

private func expectRetryClaim(
    _ persisted: RuntimeStoredSession,
    fixture: ProcessRestartFixture,
    ownerToken: String,
) {
    #expect(persisted.runReference == fixture.run)
    #expect(persisted.providerInternalSessionReference == fixture.receiptReference)
    #expect(persisted.projection == .running)
    #expect(persisted.restorationClaim?.ownerToken == ownerToken)
}

private func expectCompletedSession(_ persisted: RuntimeStoredSession) {
    #expect(persisted.projection == .completed)
    #expect(persisted.restorationClaim == nil)
}

private func expectUnusedAdapter(_ counts: RuntimeAdapterInvocationCounts) {
    #expect(counts.stream == 0)
    #expect(counts.terminalResult == 0)
}

import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-restore_resume_ownership

    /// VOY-747-restore_resume_ownership: shared file admits only one resume owner.
    /// 공유 파일에서 동일 provider run의 resume owner가 하나만 선택되는지 coordinator 경계에서 검증한다.
    /// - 검증 내용: restore 승자와 stale 결과, 중복 resume 거부, terminal 결과와 persisted projection.
    /// - 사전 조건: running session이 file store에 저장되고 두 control plane이 같은 adapter를 등록한다.
    /// - 기대 결과: 하나의 control plane만 provider terminal을 소비하고 durable 상태가 completed로 수렴한다.
    @Test
    func `shared file admits only one resume owner`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = ExternalAgentSessionReference("host-shared-restore")
        let run = RuntimeRunReference("run-shared-restore")
        let context = makeContext()
        let result = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://shared-restore.json"],
        )
        let capabilities = ownershipTerminalOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let seed = RuntimeFileStateStore(fileURL: fileURL)
        try await seed.seed(makeState([stored]))
        let terminalGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: result,
            terminalResultGate: terminalGate,
        )
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(adapter)
        try await secondPlane.register(adapter)

        let firstRestore = try await firstPlane.restore(hostReference: host, expectedContext: context)
        let secondRestore = try await secondPlane.restore(hostReference: host, expectedContext: context)
        #expect(firstRestore == .restored)
        #expect(secondRestore == .stale)
        let firstResume = Task { try await firstPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(1)
        await ownershipHandleCompetingResume(
            result: secondRestore,
            plane: secondPlane,
            host: host,
            adapter: adapter,
            terminalGate: terminalGate,
        )

        try await ownershipAssertSharedFileCompletion(
            resume: firstResume,
            expected: result,
            adapter: adapter,
            fileURL: fileURL,
        )
    }

    /// VOY-747-restore_resume_ownership: restored terminal probe failure releases its claim.
    /// terminal-result 실패 뒤 durable terminal probe 자체가 실패해도 resumption lease를 남기지 않는지 검증한다.
    /// - 검증 내용: typed persistence error, completed projection, inactive lease, durable terminal snapshot.
    /// - 사전 조건: completed event 저장 뒤 terminal-result 오류와 두 번째 load typed 오류가 연속 발생한다.
    /// - 기대 결과: typed 오류는 보존되고 같은 run의 resumption claim은 inactive 상태로 회수된다.
    @Test(arguments: OwnershipHeartbeatProbeFailure.allCases)
    private func `restored terminal probe failure releases its claim`(
        failure: OwnershipHeartbeatProbeFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-resume-terminal-probe-\(failure.rawValue)")
        let run = RuntimeRunReference("run-resume-terminal-probe-\(failure.rawValue)")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-terminal-probe"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: failure.storeError],
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
                        idempotencyKey: "restored-terminal-probe",
                        kind: .completed,
                    ),
                ],
            ],
            failsTerminalResult: true,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        await #expect(throws: failure.hostError) {
            _ = try await plane.resumeRestoredRun(hostReference: host)
        }

        #expect(await store.loadCount == 2)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().stream == 1)
    }

    /// VOY-747-restore_resume_ownership: restored adapter failure repairs only its own resume claim.
    /// 실제 resumeRestoredRun의 adapter 오류 cleanup이 persistence conflict와 unavailable을 구분하면서 replacement owner를 보존하는지
    /// 검증한다.
    /// - 검증 내용: restore/resume claim owner token, cleanup 경로, conflict/unavailable 저장 경계, exact lease recovery와
    /// replacement owner 보존.
    /// - 사전 조건: compatible restored snapshot, event-stream creation failure, same-host replacement state가 구성되어 있다.
    /// - 기대 결과: conflict는 persistenceConflict, unavailable은 persistenceFailure를 반환하고 원래 claim owner만 restored lease로
    /// 복구한다.
    @Test(arguments: OwnershipPersistenceBoundaryFailure.allCases)
    private func `restored adapter failure repairs only its own resume claim`(
        failure: OwnershipPersistenceBoundaryFailure,
    ) async throws {
        let fixture = try await ownershipMakeResumptionCleanupFixture(failure: failure)

        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let ownerToken = await fixture.plane.restorationOwnerToken
        let restoredLease = try #require(await fixture.plane.sessions[fixture.host]?.lease)
        let claimToken = try #require(await fixture.plane.sessions[fixture.host]?.stored.restorationClaim?.ownerToken)
        #expect(claimToken == ownerToken)

        let resume = Task { try await fixture.plane.resumeRestoredRun(hostReference: fixture.host) }
        if failure == .unavailable {
            await fixture.store.waitForUpdateCount(3)
            await fixture.store.replaceState(fixture.replacementState)
            await fixture.cleanupGate.open()
        }

        if failure == .conflict {
            await #expect(throws: RuntimeHostError.persistenceConflict) { try await resume.value }
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) { try await resume.value }
        }

        #expect(await fixture.adapter.counts().stream == 1)
        #expect(await fixture.store.updateCount == 3)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == restoredLease)
        #expect(await fixture.plane.sessions[fixture.host]?.lease.isAwaitingResumption == true)
        #expect(await fixture.plane.sessions[fixture.host]?.stored.restorationClaim?.ownerToken == ownerToken)
        #expect(await fixture.store.currentState()?.sessions == [fixture.replacement])
        await #expect(throws: RuntimeHostError.activeRunExists) {
            _ = try await fixture.plane.run(makeLaunch(
                host: fixture.host,
                run: RuntimeRunReference("replacement-attempt"),
                adapterID: "sdk",
            ))
        }
        #expect(await fixture.store.currentState()?.sessions == [fixture.replacement])
    }

    /// VOY-747-restore_resume_ownership: process and transport cleanup cannot revive a stale local owner.
    /// persisted claim을 replacement owner가 인수한 뒤 이전 process/transport owner의 cleanup이 local restored lease를 되살리지 않는지
    /// 검증한다.
    /// - 검증 내용: persisted owner reconciliation, stale local lease fencing, process/transport error taxonomy, provider
    /// counts.
    /// - 사전 조건: owner A의 typed interruption이 gate에서 대기하고 owner B가 expiry 이후 replacement claim을 먼저 저장한다.
    /// - 기대 결과: A는 원래 adapter 오류를 반환하고 local state는 B의 persisted claim과 inactive lease를 채택한다.
    @Test(arguments: OwnershipStaleResumptionCleanupFailure.allCases)
    private func `stale process transport cleanup cannot regain restored ownership`(
        failure: OwnershipStaleResumptionCleanupFailure,
    ) async throws {
        let fixture = ownershipMakeStaleResumptionCleanupFixture(failure: failure)
        try await fixture.ownerPlane.register(fixture.ownerAdapter)
        try await fixture.replacementPlane.register(fixture.replacementAdapter)

        #expect(try await fixture.ownerPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let ownerResume = Task {
            try await fixture.ownerPlane.resumeRestoredRun(hostReference: fixture.host)
        }
        await fixture.ownerAdapter.waitForEventStreamCount(1)

        #expect(try await fixture.replacementPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let replacementOwner = await fixture.replacementPlane.restorationOwnerToken
        await fixture.failureGate.open()

        await #expect(throws: failure.hostError) { try await ownerResume.value }

        let ownerSession = try #require(await fixture.ownerPlane.sessions[fixture.host])
        #expect(ownerSession.lease == .none)
        #expect(ownerSession.stored.restorationClaim?.ownerToken == replacementOwner)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim?.ownerToken == replacementOwner)
        #expect(await fixture.store.applyCount == 3)
        #expect(await fixture.ownerAdapter.counts().stream == 1)
        #expect(await fixture.ownerAdapter.counts().terminalResult == 0)
        #expect(await fixture.replacementAdapter.counts().stream == 0)
        #expect(await fixture.replacementAdapter.counts().terminalResult == 0)
    }

    /// VOY-747-restore_resume_fencing_load_failure: fencing load failure preserves typed interruption and deactivates
    /// local lease.
    /// processExit와 transportLoss 뒤 persisted owner fencing load가 실패해도 원래 adapter 오류와 안전한 local 상태를 보존하는지 검증한다.
    /// - 검증 내용: typed RuntimeAdapterFailureKind, bounded cleanup evidence, local non-resuming lease와 replacement claim
    /// 보존.
    /// - 사전 조건: replacement owner가 claim을 인수한 뒤 이전 owner의 fencing load가 unavailable이 된다.
    /// - 기대 결과: 이전 owner는 원래 오류를 반환하고 local lease는 none이 되며 stale replacement owner를 local에서 복구하지 않는다.
    @Test(arguments: OwnershipStaleResumptionCleanupFailure.allCases)
    private func `fencing load failure preserves typed interruption`(
        failure: OwnershipStaleResumptionCleanupFailure,
    ) async throws {
        let fixture = ownershipMakeStaleResumptionCleanupFixture(
            failure: failure,
            fencingLoadUnavailable: true,
        )
        try await fixture.ownerPlane.register(fixture.ownerAdapter)
        try await fixture.replacementPlane.register(fixture.replacementAdapter)

        #expect(try await fixture.ownerPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let ownerToken = await fixture.ownerPlane.restorationOwnerToken
        let ownerResume = Task {
            try await fixture.ownerPlane.resumeRestoredRun(hostReference: fixture.host)
        }
        await fixture.ownerAdapter.waitForEventStreamCount(1)

        #expect(try await fixture.replacementPlane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let replacementOwner = await fixture.replacementPlane.restorationOwnerToken
        await fixture.failureGate.open()

        await #expect(throws: failure.hostError) { try await ownerResume.value }

        let local = try #require(await fixture.ownerPlane.sessions[fixture.host])
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        #expect(local.lease == .none)
        #expect(local.stored.runReference == fixture.run)
        #expect(local.stored.restorationClaim?.ownerToken == ownerToken)
        #expect(persisted.restorationClaim?.ownerToken == replacementOwner)
        #expect(await fixture.ownerPlane.cleanupFailureEvidence(for: fixture.host) == RuntimeCleanupFailureEvidence(
            runReference: fixture.run,
            kind: .persistence,
        ))
        #expect(await fixture.store.loadCount == 4)
        #expect(await fixture.store.applyCount == 3)
        #expect(await fixture.ownerAdapter.counts().stream == 1)
        #expect(await fixture.ownerAdapter.counts().terminalResult == 0)
        #expect(await fixture.replacementAdapter.counts().stream == 0)
        #expect(await fixture.replacementAdapter.counts().terminalResult == 0)
        await #expect(throws: RuntimeHostError.invalidEvent) {
            _ = try await fixture.ownerPlane.resumeRestoredRun(hostReference: fixture.host)
        }
    }

    /// VOY-747-restore_resume_ownership: cross-plane host terminal wins over restoration heartbeat.
    /// 복원 stream이 열린 동안 다른 control plane이 저장한 같은 run의 host terminal을 heartbeat claim 오류보다 우선한다.
    /// - 검증 내용: stale resumer 반환 결과, 양쪽 terminal projection, durable claim 제거, provider stream 횟수.
    /// - 사전 조건: 두 control plane이 공유하는 file-backed run에서 첫 plane의 provider stream이 gate에서 대기한다.
    /// - 기대 결과: heartbeat는 store의 durable terminal로 수렴하고 stale resumer도 completed 결과를 반환한다.
    @Test
    func `cross-plane host terminal wins over restoration heartbeat`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host = ExternalAgentSessionReference("host-heartbeat-terminal")
        let run = RuntimeRunReference("run-heartbeat-terminal")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-terminal"),
            runReference: run,
            projection: .running,
        )
        try await RuntimeFileStateStore(fileURL: fileURL).seed(makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let resumingPlane = RuntimeControlPlane(
            store: RuntimeFileStateStore(fileURL: fileURL),
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await resumingPlane.register(adapter)
        #expect(try await resumingPlane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await resumingPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        let hostPlane = RuntimeControlPlane(
            store: RuntimeFileStateStore(fileURL: fileURL),
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        let terminal = try #require(try await hostPlane.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        )))

        #expect(terminal.outcome == .completed)
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await streamGate.open()
        #expect(try await resume.value.outcome == .completed)
        #expect(await resumingPlane.projection(for: host) == .completed)
        #expect(await hostPlane.projection(for: host) == .completed)
        #expect(try await RuntimeFileStateStore(fileURL: fileURL).load()?.sessions.first?.restorationClaim == nil)
        #expect(await adapter.counts().stream == 1)
    }

    /// VOY-747-restore_resume_ownership: heartbeat renewal conflict yields to same-run durable terminal.
    /// renewal 성공 뒤 cross-plane durable completed가 저장되면 다음 renewal conflict가
    /// attemptLost/persistenceConflict로 노출되기 전에 같은 run의 durable terminal이 이겨야 한다.
    /// - 검증 내용: gate/clock으로 renewal→terminal저장→conflict 순서를 고정하고 resume가 completed로 수렴하는지 검증.
    /// - 사전 조건: restored 소유자의 첫 heartbeat renewal이 성공한 뒤 provider stream은 gate에서 대기한다.
    /// - 기대 결과: 두 번째 renewal conflict 중에도 resume는 persistenceConflict 대신 durable completed를 반환한다.
    @Test
    func `heartbeat renewal conflict yields to same-run durable terminal`() async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-renewal-terminal")
        let run = RuntimeRunReference("run-heartbeat-renewal-terminal")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-renewal"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let clock = DeterministicRuntimeRestorationClock(currentDate: Date(timeIntervalSince1970: 4_102_444_800))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let resumingPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await resumingPlane.register(adapter)
        #expect(try await resumingPlane.restore(hostReference: host, expectedContext: context) == .restored)

        let resume = Task { try await resumingPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        // 1차 heartbeat 갱신이 cross-plane 저장 없이 성공하고 루프가 다시 잠들 때까지 대기한다.
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await clock.waitUntilSleeping()

        // 같은 run의 durable terminal이 cross-plane에서 저장된다.
        let hostPlane = RuntimeControlPlane(store: store)
        #expect(try await hostPlane.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))?.outcome == .completed)

        // 2차 heartbeat 갱신은 conflict지만 노출 전 durable terminal 수렴이 우선해야 한다.
        await clock.releaseSleepers()
        do {
            #expect(try await resume.value.outcome == .completed)
        } catch {
            await streamGate.open()
            Issue.record("durable terminal은 heartbeat conflict 노출보다 우선해야 한다: \(error)")
            return
        }
        #expect(await resumingPlane.projection(for: host) == .completed)
        #expect(await resumingPlane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().stream == 1)

        await streamGate.open()
    }

    /// VOY-747-restore_resume_ownership: heartbeat renewal conflict converges via exact-run read repair.
    /// heartbeat 갱신 conflict 지점에서 같은 run의 cross-plane durable terminal이
    /// persistenceConflict/attempt loss 노출보다 우선하고 exact owner finalize로 수렴하는지 검증한다.
    /// - 검증 내용: 공개 completed 결과, local/durable completed projection, lease none,
    /// local/durable restoration claim 제거, provider stream 1회와 terminalResult 0회.
    /// - 사전 조건: restored 소유자의 첫 heartbeat renewal이 성공해 다시 잠들고 provider stream은 gate에서 대기한다.
    /// - 기대 결과: 두 번째 renewal conflict 중에도 resume는 durable completed로 수렴하고 소유자 claim은 남지 않는다.
    @Test
    func `heartbeat renewal conflict converges via exact-run read repair`() async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-repair-convergence")
        let run = RuntimeRunReference("run-heartbeat-repair-convergence")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-repair"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let clock = DeterministicRuntimeRestorationClock(currentDate: Date(timeIntervalSince1970: 4_102_444_800))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let resumingPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await resumingPlane.register(adapter)
        #expect(try await resumingPlane.restore(hostReference: host, expectedContext: context) == .restored)

        let resume = Task { try await resumingPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        // 1차 heartbeat 갱신이 성공하고 heartbeat 루프가 다시 잠들 때까지 대기한다.
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await clock.waitUntilSleeping()

        // 같은 run의 durable terminal을 second plane에서 저장한다.
        let hostPlane = RuntimeControlPlane(store: store)
        #expect(try await hostPlane.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))?.outcome == .completed)

        // 2차 heartbeat 갱신은 conflict지만 provider는 여전히 gate에서 대기한다.
        await clock.releaseSleepers()
        #expect(try await resume.value.outcome == .completed)
        #expect(await resumingPlane.projection(for: host) == .completed)
        #expect(await resumingPlane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await resumingPlane.sessions[host]?.stored.restorationClaim == nil)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)

        await streamGate.open()
    }

    /// VOY-747-restore_admission_repair: provider result admission loss yields to same-run durable terminal.
    /// provider 결과 승인 경계에서 claim 만료 복구가 fencing으로 durable terminal을 채택한 뒤에도
    /// persistenceConflict가 노출되지 않고 같은 run의 durable terminal이 이겨야 한다.
    /// - 검증 내용: 만료 복구 저장 gate 중 cross-plane terminal 저장, admission loss 이후 completed 수렴,
    /// exact owner lease/claim 정리, provider 호출 횟수.
    /// - 사전 조건: restored 소유자의 claim이 clock 진행으로 만료되고 provider 결과는 heartbeat보다 먼저 도달한다.
    /// - 기대 결과: resume은 persistenceConflict 대신 durable completed를 반환하고 lease와 claim은 정리된다.
    @Test
    func `provider result admission loss yields to same-run durable terminal`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host = ExternalAgentSessionReference("host-admission-repair")
        let run = RuntimeRunReference("run-admission-repair")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let recoverySaveGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-admission-repair"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            saveGates: [3: recoverySaveGate],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        // 승인 경계에서 claim이 만료되도록 clock을 진행하고 heartbeat보다 provider 결과를 먼저 도달시킨다.
        clock.advance(by: 61)
        await streamGate.open()

        // 만료 복구 저장이 gate에서 대기하는 동안 같은 run의 durable terminal을 저장한다.
        await store.waitForSaveCount(3)
        let hostPlane = RuntimeControlPlane(store: store)
        #expect(try await hostPlane.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))?.outcome == .completed)
        await recoverySaveGate.open()

        #expect(try await resume.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await plane.sessions[host]?.stored.restorationClaim == nil)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        let counts = await adapter.counts()
        #expect(counts.stream == 1)
        #expect(counts.terminalResult == 1)
    }

    /// VOY-747-restore_resume_ownership: heartbeat persistence failure preserves resume claim.
    /// provider 소비 중 heartbeat conflict와 저장 실패를 run interruption으로 오인하지 않는지 검증한다.
    /// - 검증 내용: persistenceConflict/persistenceFailure 구분, running projection과 재개 가능한 claim 보존.
    /// - 사전 조건: restored stream은 대기하고 첫 heartbeat renewal save가 실패한다.
    /// - 기대 결과: conflict는 persistenceConflict, unavailable은 persistenceFailure이며 다음 resume이 stream을 다시 연다.
    @Test(arguments: OwnershipPersistenceBoundaryFailure.allCases)
    private func `heartbeat persistence failure preserves resume claim`(
        failure: OwnershipPersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-persistence-failure")
        let run = RuntimeRunReference("run-heartbeat-persistence-failure")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-persistence-failure"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            failingSaveNumbers: failure == .unavailable ? [3] : [],
            conflictingSaveNumbers: failure == .conflict ? [3] : [],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store, restorationHeartbeatInterval: .milliseconds(10))
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        let firstResume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await store.waitForSaveCount(3)
        if failure == .conflict {
            await #expect(throws: RuntimeHostError.persistenceConflict) { try await firstResume.value }
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) { try await firstResume.value }
        }
        try #require(await plane.projection(for: host) == .running)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
        #expect(await store.currentState()?.sessions.first?.restorationClaim != nil)
        #expect(await store.saveCount == 3)

        let retry = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(2)
        retry.cancel()
        await #expect(throws: CancellationError.self) { try await retry.value }
    }

    /// VOY-747-restore_resume_ownership: typed terminal probe failure survives heartbeat conflict.
    /// renewal conflict 뒤 terminal probe의 persisted-state 오류가 heartbeat persistence 오류로 뭉개지지 않는지 검증한다.
    /// - 검증 내용: save #3 conflict, load #2 typed invalid/unsupported error, exact error, claim과 retryability.
    /// - 사전 조건: restored running session과 대기 provider stream이 구성되고 terminal probe load에 typed 오류가 주입된다.
    /// - 기대 결과: 원래 typed 오류가 반환되고 running claim이 복구된다.
    @Test(arguments: OwnershipHeartbeatProbeFailure.allCases)
    private func `typed terminal probe failure survives heartbeat conflict`(
        failure: OwnershipHeartbeatProbeFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-probe-\(failure.rawValue)")
        let run = RuntimeRunReference("run-heartbeat-probe-\(failure.rawValue)")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-probe"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: failure.storeError],
            conflictingSaveNumbers: [3],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store, restorationHeartbeatInterval: .milliseconds(10))
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        let firstResume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await store.waitForSaveCount(3)
        await #expect(throws: failure.hostError) { try await firstResume.value }
        #expect(await store.saveCount == 3)
        #expect(await store.loadCount == 2)
        #expect(await plane.projection(for: host) == .running)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
        #expect(await store.currentState()?.sessions.first?.restorationClaim != nil)

        let retry = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(2)
        retry.cancel()
        await #expect(throws: CancellationError.self) { try await retry.value }
        #expect(await adapter.counts().stream == 2)
    }
}

enum OwnershipPersistenceBoundaryFailure: String, CaseIterable {
    case conflict
    case unavailable
}

enum OwnershipStaleResumptionCleanupFailure: String, CaseIterable {
    case processExit
    case transportLoss

    var kind: RuntimeAdapterFailureKind {
        switch self {
        case .processExit: .processExit
        case .transportLoss: .transportLoss
        }
    }

    var hostError: RuntimeHostError {
        .adapterFailure(kind, RuntimeDiagnosticCode(rawValue))
    }
}

enum OwnershipHeartbeatProbeFailure: String, CaseIterable {
    case invalidPersistedState
    case unsupportedSchemaVersion

    var storeError: RuntimeStateStoreError {
        switch self {
        case .invalidPersistedState:
            .invalidSnapshot
        case .unsupportedSchemaVersion:
            .unsupportedSchemaVersion(999)
        }
    }

    var hostError: RuntimeHostError {
        switch self {
        case .invalidPersistedState:
            .invalidPersistedState
        case .unsupportedSchemaVersion:
            .unsupportedSchemaVersion(999)
        }
    }
}

func ownershipTerminalOnlyCapabilities() -> RuntimeCapabilities {
    RuntimeCapabilities(
        discovery: .unsupported,
        eventStream: .unsupported,
        approval: .unsupported,
        cancellation: .unsupported,
        queuedInput: .unsupported,
        terminalResult: .supported,
        sameIdentityResume: .supported,
    )
}

func ownershipMakeHostTerminal(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    sequence: UInt64,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .host,
        providerEventID: ProviderEventID("ownership-host-terminal-\(sequence)"),
        sequence: sequence,
        idempotencyKey: RuntimeIdempotencyKey("ownership-terminal-\(sequence)"),
        timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
        externalAgentSessionReference: host,
        runReference: run,
        kind: .completed,
    )
}

private func ownershipHandleCompetingResume(
    result: RuntimeRestoreResult,
    plane: RuntimeControlPlane,
    host: ExternalAgentSessionReference,
    adapter: DeterministicRuntimeAdapter,
    terminalGate: RuntimeTestGate,
) async {
    if result == .restored {
        let duplicateResume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(2)
        await terminalGate.open()
        _ = try? await duplicateResume.value
    } else {
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        await terminalGate.open()
    }
}

private func ownershipAssertSharedFileCompletion(
    resume: Task<RuntimeResult, Error>,
    expected: RuntimeResult,
    adapter: DeterministicRuntimeAdapter,
    fileURL: URL,
) async throws {
    #expect(try await resume.value == expected)
    #expect(await adapter.counts().stream == 0)
    let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
    #expect(persisted.sessions.first?.projection == .completed)
}

private struct OwnershipResumptionCleanupFixture {
    let context: RuntimeContextPolicy
    let host: ExternalAgentSessionReference
    let replacement: RuntimeStoredSession
    let replacementState: RuntimeStoredState
    let cleanupGate: RuntimeTestGate
    let store: DeterministicHostMutationRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

private struct OwnershipStaleResumptionCleanupFixture {
    let context: RuntimeContextPolicy
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let failureGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let ownerPlane: RuntimeControlPlane
    let replacementPlane: RuntimeControlPlane
    let ownerAdapter: DeterministicRuntimeAdapter
    let replacementAdapter: DeterministicRuntimeAdapter
}

private func ownershipMakeStaleResumptionCleanupFixture(
    failure: OwnershipStaleResumptionCleanupFailure,
    fencingLoadUnavailable: Bool = false,
) -> OwnershipStaleResumptionCleanupFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let ownerClock = DeterministicRuntimeRestorationClock(currentDate: now)
    let replacementClock = DeterministicRuntimeRestorationClock(currentDate: now.addingTimeInterval(61))
    let context = makeContext()
    let host = ExternalAgentSessionReference("host-stale-cleanup-\(failure.rawValue)")
    let run = RuntimeRunReference("run-stale-cleanup-\(failure.rawValue)")
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("stale-cleanup-receipt"),
        runReference: run,
        projection: .running,
    )
    let failureGate = RuntimeTestGate()
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        loadErrors: fencingLoadUnavailable ? [4: .unavailable] : [:],
    )
    let ownerAdapter = DeterministicRuntimeAdapter(
        id: "sdk",
        eventStreamRuntimeFailure: RuntimeAdapterFailure(
            kind: failure.kind,
            diagnosticCode: RuntimeDiagnosticCode(failure.rawValue),
        ),
        eventStreamRuntimeFailureGate: failureGate,
    )
    return OwnershipStaleResumptionCleanupFixture(
        context: context,
        host: host,
        run: run,
        failureGate: failureGate,
        store: store,
        ownerPlane: RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: ownerClock.runtimeClock,
        ),
        replacementPlane: RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: replacementClock.runtimeClock,
        ),
        ownerAdapter: ownerAdapter,
        replacementAdapter: DeterministicRuntimeAdapter(id: "sdk"),
    )
}

private func ownershipMakeResumptionCleanupFixture(
    failure: OwnershipPersistenceBoundaryFailure,
) async throws -> OwnershipResumptionCleanupFixture {
    let context = makeContext()
    let host = ExternalAgentSessionReference("host-resume-cleanup-\(failure.rawValue)")
    let replacement = ownershipMakeResumptionReplacement(failure: failure, host: host, context: context)
    let stored = ownershipMakeResumptionStored(failure: failure, host: host, context: context)
    let replacementState = makeState([replacement])
    let cleanupGate = RuntimeTestGate()
    let store = DeterministicHostMutationRuntimeStateStore(
        state: makeState([stored]),
        failingUpdateNumbers: failure == .unavailable ? [3] : [],
        conflictingUpdateStates: failure == .conflict ? [3: replacementState] : [:],
        updateGates: failure == .unavailable ? [3: cleanupGate] : [:],
    )
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: .allSupported,
        eventsByLaunch: [[]],
        eventStreamFailure: .creation,
    )
    let plane = RuntimeControlPlane(store: store)
    try await plane.register(adapter)
    return OwnershipResumptionCleanupFixture(
        context: context,
        host: host,
        replacement: replacement,
        replacementState: replacementState,
        cleanupGate: cleanupGate,
        store: store,
        adapter: adapter,
        plane: plane,
    )
}

private func ownershipMakeResumptionReplacement(
    failure: OwnershipPersistenceBoundaryFailure,
    host: ExternalAgentSessionReference,
    context: RuntimeContextPolicy,
) -> RuntimeStoredSession {
    RuntimeStoredSession(
        externalAgentSessionReference: host,
        providerInternalSessionReference: nil,
        runReference: RuntimeRunReference("replacement-\(failure.rawValue)"),
        adapterID: RuntimeAdapterID("sdk"),
        adapterVersion: "1.0.0",
        capabilitySnapshot: .allSupported,
        storedContext: RuntimeStoredContext(contextPolicy: context),
        projection: .launching,
        providerLaunchAttempted: true,
    )
}

private func ownershipMakeResumptionStored(
    failure: OwnershipPersistenceBoundaryFailure,
    host: ExternalAgentSessionReference,
    context: RuntimeContextPolicy,
) -> RuntimeStoredSession {
    RuntimeStoredSession(
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-cleanup"),
        runReference: RuntimeRunReference("run-resume-cleanup-\(failure.rawValue)"),
        adapterID: RuntimeAdapterID("sdk"),
        adapterVersion: "1.0.0",
        capabilitySnapshot: .allSupported,
        storedContext: RuntimeStoredContext(contextPolicy: context),
        projection: .running,
    )
}

struct OwnershipResumeClaimRaceFixture {
    let host: ExternalAgentSessionReference
    let saveGate: RuntimeTestGate
    let streamGate: RuntimeTestGate
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

func ownershipMakeResumeClaimRace() async throws -> OwnershipResumeClaimRaceFixture {
    let host = ExternalAgentSessionReference("host-resume-claim")
    let run = RuntimeRunReference("run-resume-claim")
    let context = makeContext()
    let saveGate = RuntimeTestGate()
    let streamGate = RuntimeTestGate()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        runReference: run,
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        failingSaveNumbers: [2],
        saveGates: [2: saveGate],
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
                    idempotencyKey: "resume-claim-completed",
                    kind: .completed,
                ),
            ],
        ],
        eventStreamGate: streamGate,
    )
    let plane = RuntimeControlPlane(store: store)
    try await plane.register(adapter)
    #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
    return OwnershipResumeClaimRaceFixture(
        host: host,
        saveGate: saveGate,
        streamGate: streamGate,
        store: store,
        adapter: adapter,
        plane: plane,
    )
}

func ownershipMakeRunningSession(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    context: RuntimeContextPolicy,
) -> RuntimeStoredSession {
    makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
        runReference: run,
        projection: .running,
    )
}

func ownershipWaitForResumeClaimBoundary(
    host: ExternalAgentSessionReference,
    on plane: RuntimeControlPlane,
) async throws -> (awaitingResumption: Bool, persistenceWaiterCount: Int) {
    for _ in 0 ..< 10000 {
        let awaitingResumption = await plane.sessions[host]?.lease.isAwaitingResumption == true
        let persistenceWaiterCount = await plane.persistenceMutationWaiters.count
        if !awaitingResumption || persistenceWaiterCount > 0 {
            return (awaitingResumption, persistenceWaiterCount)
        }
        await Task.yield()
    }
    throw RuntimeHostError.invalidEvent
}

func ownershipWaitForPersistenceWaiters(
    _ count: Int,
    on plane: RuntimeControlPlane,
) async throws {
    for _ in 0 ..< 10000 {
        if await plane.persistenceMutationWaiters.count >= count { return }
        await Task.yield()
    }
    throw RuntimeHostError.invalidEvent
}

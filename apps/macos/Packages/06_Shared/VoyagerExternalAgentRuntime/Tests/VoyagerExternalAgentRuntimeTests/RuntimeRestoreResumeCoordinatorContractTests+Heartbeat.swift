import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    /// VOY-747-future_coordinator: heartbeat waits through the injected restoration clock.
    /// heartbeat가 wall-clock sleep 대신 주입된 restoration clock을 사용하는지 public coordinator 상태로 검증한다.
    /// - 검증 내용: 복원 후 heartbeat 대기와 provider consumption의 deterministic 정리.
    /// - 사전 조건: claim 없는 compatible running session과 deterministic sleeper가 구성되어 있다.
    /// - 기대 결과: heartbeat가 injected sleeper에 등록되고 provider 호출은 취소 후 종료된다.
    @Test
    func `heartbeat uses injected time`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "future-heartbeat-clock"
        let run = RuntimeRunReference("future-heartbeat-clock-run")
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .restored)
        let resume = Task {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        await adapter.waitForEventStreamCount(1)
        for _ in 0 ..< 100 {
            if await clock.isSleeping() { break }
            await Task.yield()
        }
        #expect(await clock.isSleeping())
        resume.cancel()
        await eventStreamGate.open()
        _ = try? await resume.value
    }

    /// VOY-747-future_coordinator: a stale owner cannot renew a replacement claim.
    /// replacement owner가 유효한 동안 이전 owner가 restoration claim을 갱신하지 못하는 clock 경계를 검증한다.
    /// - 검증 내용: 이전 owner claim의 injected expiry와 restore 결과가 replacement 획득을 허용하는지 확인한다.
    /// - 사전 조건: old owner의 claim은 injected now 기준 만료되었고 실제 wall-clock 기준으로는 아직 미래다.
    /// - 기대 결과: stale owner는 renew하지 못하고 replacement owner가 restored 결과를 얻는다.
    @Test
    func `stale owner cannot renew replacement claim`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "future-stale-owner"
        let run = RuntimeRunReference("future-stale-owner-run")
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            projection: .running,
            restorationClaim: RuntimeRestorationClaim(
                ownerToken: "stale-owner",
                expiresAt: now.addingTimeInterval(-1),
            ),
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        try await plane.register(adapter)

        let result = try await plane.restore(hostReference: host, expectedContext: makeContext())
        #expect(result == .restored)
        let replacementClaim = try #require(await store.currentState()?.sessions.first?.restorationClaim)
        #expect(replacementClaim.ownerToken != "stale-owner")
        let resume = Task {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        await adapter.waitForEventStreamCount(1)
        for _ in 0 ..< 100 {
            if await clock.isSleeping() { break }
            await Task.yield()
        }
        #expect(await clock.isSleeping())
        resume.cancel()
        await eventStreamGate.open()
        _ = try? await resume.value
    }

    // MARK: - VOY-747-heartbeat

    /// VOY-747-heartbeat: heartbeat renewal extends the owned restoration claim with injected time.
    /// provider 소비가 진행되는 동안 heartbeat가 동일한 owner의 claim 만료를 60초 연장하는지 검증한다.
    /// - 검증 내용: injected sleeper 해제 뒤 단일 renewal apply, 정확한 owner와 expiresAt, provider 호출 횟수.
    /// - 사전 조건: fixed Date 기반 compatible restored run과 event stream gate가 구성되어 있다.
    /// - 기대 결과: restore/claim/heartbeat 순서로 apply가 세 번 발생하고 claim은 `now + 60s`가 된다.
    @Test
    func `heartbeat renewal extends owned claim with injected clock`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "heartbeat-renewal"
        let run = RuntimeRunReference("heartbeat-renewal-run")
        let capabilities = makeHeartbeatCapabilities()
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .restored)

        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await store.waitForApplyCount(3)

        let persisted = try #require(await store.currentState()?.sessions.first)
        let claim = try #require(persisted.restorationClaim)
        let ownerToken = await plane.restorationOwnerToken
        #expect(claim.ownerToken == ownerToken)
        #expect(claim.expiresAt == now.addingTimeInterval(60))
        #expect(await store.applyCount == 3)
        #expect(await (adapter.counts()).stream == 1)
        #expect(await (adapter.counts()).terminalResult == 0)

        resume.cancel()
        await eventStreamGate.open()
        await #expect(throws: CancellationError.self) { try await resume.value }
    }

    /// VOY-747-heartbeat: host terminal wins a heartbeat renewal race.
    /// 다른 host coordinator가 terminal을 저장하면 진행 중인 provider resume이 durable terminal을 채택하는지 검증한다.
    /// - 검증 내용: host terminal apply, heartbeat CAS conflict, terminal adoption, provider eventStream 횟수.
    /// - 사전 조건: 두 plane이 하나의 deterministic store를 공유하고 resuming provider stream이 대기한다.
    /// - 기대 결과: completed terminal이 유일한 결과가 되고 heartbeat는 replacement claim이나 provider result를 쓰지 않는다.
    @Test
    func `host terminal wins heartbeat race`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "heartbeat-host-terminal"
        let run = RuntimeRunReference("heartbeat-host-terminal-run")
        let context = makeContext()
        let capabilities = makeHeartbeatCapabilities()
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let resumingPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await resumingPlane.register(adapter)
        try #require(await resumingPlane.restore(hostReference: host, expectedContext: context) == .restored)

        let resume = Task { try await resumingPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await clock.waitUntilSleeping()

        let hostPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        let hostTerminal = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("heartbeat-host-terminal-event"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("heartbeat-host-terminal-key"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .completed,
        )
        #expect(try await hostPlane.ingestHostEvent(hostTerminal)?.outcome == .completed)

        await clock.releaseSleepers()
        await store.waitForApplyCount(4)
        for _ in 0 ..< 100 {
            if await resumingPlane.projection(for: host) == .completed { break }
            await Task.yield()
        }
        await eventStreamGate.open()
        #expect(try await resume.value.outcome == .completed)

        #expect(await store.applyCount == 4)
        #expect(await (3 ... 4).contains(store.loadCount))
        #expect(await resumingPlane.projection(for: host) == .completed)
        #expect(await hostPlane.projection(for: host) == .completed)
        #expect(await store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await (adapter.counts()).stream == 1)
        #expect(await (adapter.counts()).terminalResult == 0)
    }

    /// VOY-747-heartbeat: an expired heartbeat claim is reacquirable by the same coordinator.
    /// replacement owner가 없는 상태에서 heartbeat claim이 만료되어도 같은 coordinator가 다시 restore/resume할 수 있는지 검증한다.
    /// - 검증 내용: 만료 claim 정리, inactive local lease, 단일 cleanup apply, 재복원과 provider receipt의 재사용.
    /// - 사전 조건: deterministic clock이 첫 heartbeat 이후 claim TTL을 넘기고 provider stream은 cleanup 경계에서 대기한다.
    /// - 기대 결과: 첫 resume은 persistenceConflict를 반환하고 claim을 비운 뒤, 같은 coordinator가 새 claim으로 완료한다.
    @Test
    func `expired heartbeat claim is reacquirable by same coordinator`() async throws {
        let fixture = makeExpiredHeartbeatFixture()
        let fixtureContext = fixture.context
        let context = makeContext()
        let host = fixtureContext.host
        let run = fixtureContext.run
        let streamGate = fixtureContext.streamGate
        let store = fixtureContext.store
        let adapter = fixtureContext.adapter
        let plane = fixtureContext.plane
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let firstResume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await fixture.clock.waitUntilSleeping()
        let initialDate = fixture.clock.currentDate
        fixture.clock.advance(by: 61)
        #expect(fixture.clock.runtimeClock.now() == initialDate.addingTimeInterval(61))
        await fixture.clock.releaseSleepers()
        for _ in 0 ..< 1000 {
            if await plane.sessions[host]?.lease != .resuming(1) { break }
            await Task.yield()
        }
        await streamGate.open()
        await #expect(throws: RuntimeHostError.persistenceConflict) { try await firstResume.value }

        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await store.applyCount == 3)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        #expect(await store.applyCount == 4)
        let result = try await plane.resumeRestoredRun(hostReference: host)
        await adapter.waitForTerminalResultCount(1)
        await assertExpiredHeartbeatRecovery(
            result: result,
            run: run,
            context: fixtureContext,
        )
    }

    /// VOY-747-heartbeat: expired owner cannot renew a replacement claim.
    /// replacement owner가 만료된 이전 claim을 인수한 뒤 old provider가 renewal을 시도하는 stale-owner 경계를 검증한다.
    /// - 검증 내용: 두 injected clock의 expiry, replacement claim 보존, old heartbeat의 conflict와 provider 결과 차단.
    /// - 사전 조건: first plane은 원래 시각, second plane은 61초 뒤 시각으로 같은 store를 사용한다.
    /// - 기대 결과: second owner만 claim을 보존하고 old owner는 persistenceConflict와 zero terminal commit으로 종료한다.
    @Test
    func `expired owner cannot renew replacement claim`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let originalClock = DeterministicRuntimeRestorationClock(currentDate: now)
        let replacementClock = DeterministicRuntimeRestorationClock(currentDate: now.addingTimeInterval(61))
        let host: ExternalAgentSessionReference = "heartbeat-expired-owner"
        let run = RuntimeRunReference("heartbeat-expired-owner-run")
        let capabilities = makeHeartbeatCapabilities()
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let oldAdapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let replacementAdapter = DeterministicRuntimeAdapter(id: "sdk", capabilities: capabilities)
        let oldPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: originalClock.runtimeClock,
        )
        let replacementPlane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: replacementClock.runtimeClock,
        )
        try await oldPlane.register(oldAdapter)
        try await replacementPlane.register(replacementAdapter)
        #expect(try await oldPlane.restore(hostReference: host, expectedContext: makeContext()) == .restored)

        let resume = Task { try await oldPlane.resumeRestoredRun(hostReference: host) }
        await oldAdapter.waitForEventStreamCount(1)
        await originalClock.waitUntilSleeping()
        #expect(try await replacementPlane.restore(
            hostReference: host,
            expectedContext: makeContext(),
        ) == .restored)

        await originalClock.releaseSleepers()
        await store.waitForApplyCount(4)
        for _ in 0 ..< 100 {
            if await oldPlane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none { break }
            await Task.yield()
        }
        await eventStreamGate.open()
        await #expect(throws: RuntimeHostError.persistenceConflict) { try await resume.value }

        let persisted = try #require(await store.currentState()?.sessions.first)
        let oldOwner = await oldPlane.restorationOwnerToken
        let replacementOwner = await replacementPlane.restorationOwnerToken
        let replacementClaim = try #require(persisted.restorationClaim)
        #expect(replacementClaim.ownerToken == replacementOwner)
        #expect(replacementClaim.ownerToken != oldOwner)
        #expect(await store.applyCount == 4)
        #expect(await (oldAdapter.counts()).stream == 1)
        #expect(await (oldAdapter.counts()).terminalResult == 0)
        #expect(await (replacementAdapter.counts()).stream == 0)
        #expect(await (replacementAdapter.counts()).terminalResult == 0)
    }

    /// VOY-747-heartbeat: a second heartbeat CAS conflict remains persistenceConflict.
    /// 첫 renewal과 단 한 번의 repair가 모두 충돌하면 최종 read-only reconcile이 오류 분류를 보존하는지 검증한다.
    /// - 검증 내용: initial apply, one repair apply, read-only loads, persistenceConflict와 provider 호출 횟수.
    /// - 사전 조건: heartbeat renewal apply 번호 3과 repair apply 번호 4가 deterministic conflict로 설정되어 있다.
    /// - 기대 결과: 네 apply 시도 뒤 추가 repair 없이 persistenceConflict가 반환되고 running retry claim이 남는다.
    @Test
    func `second heartbeat conflict remains persistenceConflict`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "heartbeat-second-conflict"
        let run = RuntimeRunReference("heartbeat-second-conflict-run")
        let capabilities = makeHeartbeatCapabilities()
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            conflictingSaveNumbers: [3, 4],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .restored)

        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await clock.waitUntilSleeping()
        let current = try #require(await store.currentState()?.sessions.first)
        await store.replaceState(makeState([current.withProjection(.eventProjected)]))
        await clock.releaseSleepers()
        await store.waitForApplyCount(4)
        for _ in 0 ..< 100 {
            if await plane.sessions[host]?.lease.isAwaitingResumption == true { break }
            await Task.yield()
        }
        await eventStreamGate.open()
        await #expect(throws: RuntimeHostError.persistenceConflict) { try await resume.value }

        let persisted = try #require(await store.currentState()?.sessions.first)
        let ownerToken = await plane.restorationOwnerToken
        #expect(persisted.projection == .eventProjected)
        #expect(persisted.restorationClaim?.ownerToken == ownerToken)
        #expect(await store.applyCount == 4)
        // 단말 우선권 수선: 경합 실패 노출 전 durable terminal 재조회 1회가 추가된다.
        #expect(await store.loadCount == 5)
        #expect(await (adapter.counts()).stream == 1)
        #expect(await (adapter.counts()).terminalResult == 0)
    }

    /// VOY-747-heartbeat: persistence unavailable restores the retry claim.
    /// heartbeat 저장소가 unavailable이면 running run을 interrupted로 오인하지 않고 재개 claim으로 되돌리는지 검증한다.
    /// - 검증 내용: persistenceFailure 분류, local restored lease, durable running projection/claim, provider 횟수.
    /// - 사전 조건: heartbeat renewal apply 번호 3이 unavailable이고 provider stream은 gate에서 대기한다.
    /// - 기대 결과: 세 번째 apply 뒤 persistenceFailure가 반환되고 다음 resume을 위한 claim이 보존된다.
    @Test
    func `heartbeat persistence unavailable restores retry claim`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "heartbeat-unavailable"
        let run = RuntimeRunReference("heartbeat-unavailable-run")
        let capabilities = makeHeartbeatCapabilities()
        let eventStreamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            externalAgentSessionReference: host,
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            failingSaveNumbers: [3],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: eventStreamGate,
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .restored)

        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await store.waitForApplyCount(3)
        for _ in 0 ..< 100 {
            if await plane.sessions[host]?.lease.isAwaitingResumption == true { break }
            await Task.yield()
        }
        await eventStreamGate.open()
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await resume.value }

        let persisted = try #require(await store.currentState()?.sessions.first)
        let ownerToken = await plane.restorationOwnerToken
        #expect(persisted.projection == .running)
        #expect(persisted.restorationClaim?.ownerToken == ownerToken)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await store.applyCount == 3)
        // 단말 우선권 수선: 경합 실패 노출 전 durable terminal 재조회 1회가 추가된다.
        #expect(await store.loadCount == 3)
        #expect(await (adapter.counts()).stream == 1)
        #expect(await (adapter.counts()).terminalResult == 0)
    }
}

private func makeHeartbeatCapabilities() -> RuntimeCapabilities {
    RuntimeCapabilities(
        discovery: .supported,
        eventStream: .supported,
        approval: .supported,
        cancellation: .supported,
        queuedInput: .supported,
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

private struct ExpiredHeartbeatRecoveryContext {
    let plane: RuntimeControlPlane
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let streamGate: RuntimeTestGate
}

private struct ExpiredHeartbeatFixture {
    let clock: DeterministicRuntimeRestorationClock
    let context: ExpiredHeartbeatRecoveryContext
}

private func makeExpiredHeartbeatFixture() -> ExpiredHeartbeatFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let runtimeClock = RuntimeRestorationClock(
        now: { clock.currentDate },
        sleep: { duration in try await clock.runtimeClock.sleep(duration) },
    )
    let host: ExternalAgentSessionReference = "heartbeat-expired-same-coordinator"
    let run = RuntimeRunReference("heartbeat-expired-same-coordinator-run")
    let context = makeContext()
    let streamGate = RuntimeTestGate()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("heartbeat-expired-receipt"),
        runReference: run,
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        eventsByLaunch: [
            [
                makeEvent(
                    host: host,
                    run: run,
                    sequence: 1,
                    idempotencyKey: "heartbeat-expired-completed",
                    kind: .completed,
                ),
            ],
        ],
        eventStreamRuntimeFailuresByLaunch: [
            1: RuntimeAdapterFailure(
                kind: .processExit,
                diagnosticCode: RuntimeDiagnosticCode("heartbeat-expired-provider"),
            ),
        ],
        eventStreamRuntimeFailureGate: streamGate,
    )
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: runtimeClock,
    )
    return ExpiredHeartbeatFixture(
        clock: clock,
        context: ExpiredHeartbeatRecoveryContext(
            plane: plane,
            store: store,
            adapter: adapter,
            host: host,
            run: run,
            streamGate: streamGate,
        ),
    )
}

private func assertExpiredHeartbeatRecovery(
    result: RuntimeResult,
    run: RuntimeRunReference,
    context: ExpiredHeartbeatRecoveryContext,
) async {
    #expect(result.runReference == run)
    #expect(result.outcome == .completed)
    #expect(await context.plane.projection(for: context.host) == .completed)
    #expect(await context.store.currentState()?.sessions.first?.restorationClaim == nil)
    let counts = await context.adapter.counts()
    #expect(counts.stream == 2)
    #expect(counts.terminalResult == 1)
}

import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-review_regressions

    /// VOY-747-review_p1_1: host terminal arrives between restore and public resume.
    /// 복원 claim을 만든 뒤 같은 control plane에서 host terminal을 저장하고 public resume을 호출하는 경계를 검증한다.
    /// - 검증 내용: durable terminal projection, exact restored lease finalization, provider consumption call count.
    /// - 사전 조건: running session이 restored lease를 얻은 직후 같은 run의 host completed event를 수신한다.
    /// - 기대 결과: resume은 저장된 terminal을 반환하고 lease는 none이 되며 provider event/terminal 호출은 없다.
    @Test
    func `host terminal before resume finalizes restored owner`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "review-p1-1-host"
        let run = RuntimeRunReference("review-p1-1-run")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("review-p1-1-receipt"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let terminal = try #require(try await plane.ingestHostEvent(
            RuntimeEventEnvelope(
                source: .host,
                providerEventID: ProviderEventID("review-p1-1-terminal"),
                sequence: 1,
                idempotencyKey: RuntimeIdempotencyKey("review-p1-1-terminal"),
                timestamp: now,
                externalAgentSessionReference: host,
                runReference: run,
                kind: .completed,
            ),
        ))

        let resumed = try await plane.resumeRestoredRun(hostReference: host)
        let persisted = try #require(await store.currentState()?.sessions.first)
        let counts = await adapter.counts()

        #expect(terminal == RuntimeResult(runReference: run, outcome: .completed, artifactReferences: []))
        #expect(resumed == terminal)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        #expect(counts.stream == 0)
        #expect(counts.terminalResult == 0)
    }

    /// VOY-747-review_p1_2: owned expired claim is recovered after an adapter interruption.
    /// provider interruption이 claim 만료 경계에서 발생해도 만료 claim을 복구하고 즉시 같은 plane의 restore를 허용하는지 검증한다.
    /// - 검증 내용: owned expired claim의 durable clear, local lease 비활성화, immediate restore 재획득.
    /// - 사전 조건: restored resume이 provider stream 경계에서 대기하고 injected clock이 claim expiry로 전진한다.
    /// - 기대 결과: 원래 typed interruption은 유지되고 claim은 지워지며 다음 restore가 같은 run을 재획득한다.
    @Test(arguments: ReviewAdapterInterruption.allCases)
    private func `expired owned claim is cleared before restore retry`(
        interruption: ReviewAdapterInterruption,
    ) async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let failureGate = RuntimeTestGate()
        let host = ExternalAgentSessionReference("review-p1-2-host-\(interruption.rawValue)")
        let run = RuntimeRunReference("review-p1-2-run-\(interruption.rawValue)")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("review-p1-2-receipt"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventStreamRuntimeFailure: RuntimeAdapterFailure(
                kind: interruption.kind,
                diagnosticCode: RuntimeDiagnosticCode(interruption.rawValue),
            ),
            eventStreamRuntimeFailureGate: failureGate,
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
        clock.advance(by: 60)
        await failureGate.open()

        await #expect(throws: interruption.hostError) { try await resume.value }

        let persistedAfterFailure = try #require(await store.currentState()?.sessions.first)
        let ownerToken = await plane.restorationOwnerToken
        #expect(persistedAfterFailure.runReference == run)
        #expect(persistedAfterFailure.restorationClaim == nil)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await plane.sessions[host]?.stored.restorationClaim == nil)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        #expect(await store.currentState()?.sessions.first?.restorationClaim?.ownerToken == ownerToken)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-review_p1_2: caller cancellation clears an owned claim that expires during resumed consumption.
    /// 복원 소비가 대기하는 동안 claim이 만료되고 caller가 취소해도 만료 claim이 재활성화되지 않는지 검증한다.
    /// - 검증 내용: exact CancellationError, durable claim clear, local lease 비활성화, immediate restore 재획득.
    /// - 사전 조건: terminal-only resume이 provider 결과를 기다리는 동안 injected clock이 claim expiry로 전진한다.
    /// - 기대 결과: 취소 분류를 유지하면서 claim과 lease를 정리하고 같은 run의 다음 restore를 허용한다.
    @Test
    func `expired owned claim is cleared after caller cancellation`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let streamGate = RuntimeTestGate()
        let host: ExternalAgentSessionReference = "review-p1-2-cancel-host"
        let run = RuntimeRunReference("review-p1-2-cancel-run")
        let context = makeContext()
        let capabilities = reviewStreamOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("review-p1-2-cancel-receipt"),
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
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
        await clock.waitUntilSleeping()
        clock.advance(by: 60)
        resume.cancel()
        await streamGate.open()

        await #expect(throws: CancellationError.self) { try await resume.value }
        #expect(await store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        #expect(await plane.sessions[host]?.stored.runReference == run)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-review_p1_3: typed terminal probe errors survive process and transport interruption.
    /// terminal probe의 persisted-state 오류가 원래 adapter interruption으로 대체되지 않는지 네 조합으로 검증한다.
    /// - 검증 내용: invalidPersistedState/unsupportedSchemaVersion의 exact propagation과 retryable owner recovery.
    /// - 사전 조건: processExit 또는 transportLoss 뒤 첫 persisted terminal probe load에 typed 오류를 주입한다.
    /// - 기대 결과: typed 오류가 그대로 반환되고 running projection과 restored claim이 보존되며 provider 호출은 bounded다.
    @Test(arguments: ReviewTerminalProbeScenario.allCases)
    private func `typed terminal probe errors preserve interruption boundary`(
        scenario: ReviewTerminalProbeScenario,
    ) async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let failureGate = RuntimeTestGate()
        let host = ExternalAgentSessionReference("review-p1-3-host-\(scenario.rawValue)")
        let run = RuntimeRunReference("review-p1-3-run-\(scenario.rawValue)")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("review-p1-3-receipt"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: scenario.storeError],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventStreamRuntimeFailure: RuntimeAdapterFailure(
                kind: scenario.interruption.kind,
                diagnosticCode: RuntimeDiagnosticCode(scenario.interruption.rawValue),
            ),
            eventStreamRuntimeFailureGate: failureGate,
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
        clock.advance(by: 60)
        await failureGate.open()

        await #expect(throws: scenario.hostError) { try await resume.value }

        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(await store.loadCount == 2)
        #expect(await plane.projection(for: host) == .running)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(persisted.restorationClaim == nil)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-review_p1_3: typed errors from the fencing read are not masked by adapter interruption.
    /// 첫 terminal probe의 transient failure 뒤 owner fencing load가 typed persistence 오류를 반환하는 경계를 검증한다.
    /// - 검증 내용: invalidPersistedState/unsupportedSchemaVersion 전파, local owner 비활성화, cleanup evidence 기록.
    /// - 사전 조건: load #2는 unavailable, load #3은 typed 오류이며 provider는 processExit 또는 transportLoss를 반환한다.
    /// - 기대 결과: 두 번째 load의 typed 오류가 우선하고 stale local resuming owner는 남지 않는다.
    @Test(arguments: ReviewTerminalProbeScenario.allCases)
    private func `typed fencing errors preserve persistence taxonomy`(
        scenario: ReviewTerminalProbeScenario,
    ) async throws {
        let failureGate = RuntimeTestGate()
        let host = ExternalAgentSessionReference("review-p1-3-fence-host-\(scenario.rawValue)")
        let run = RuntimeRunReference("review-p1-3-fence-run-\(scenario.rawValue)")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("review-p1-3-fence-receipt"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: .unavailable, 3: scenario.storeError],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventStreamRuntimeFailure: RuntimeAdapterFailure(
                kind: scenario.interruption.kind,
                diagnosticCode: RuntimeDiagnosticCode(scenario.interruption.rawValue),
            ),
            eventStreamRuntimeFailureGate: failureGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await failureGate.open()

        await #expect(throws: scenario.hostError) { try await resume.value }
        #expect(await store.loadCount == 3)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
            runReference: run,
            kind: .persistence,
        ))
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-review_p1_4: fencing load adopts a same-run terminal after a transient first probe failure.
    /// 첫 terminal probe가 transient persistence failure를 반환한 뒤 fence read가 저장된 같은 run terminal을 찾는 경계를 검증한다.
    /// - 검증 내용: second-read terminal adoption, exact resumption owner finalization, adapter interruption suppression.
    /// - 사전 조건: load #2는 unavailable을 반환하고 load #3 직전에 같은 run의 completed state로 교체된다.
    /// - 기대 결과: completed result가 반환되고 lease와 claim은 inactive가 되며 provider terminal 호출은 추가되지 않는다.
    @Test
    func `fencing load adopts same run terminal after transient probe failure`() async throws {
        let fixture = makeReviewP1FourFixture()
        try await fixture.plane.register(fixture.adapter)

        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)
        let resume = Task { try await fixture.plane.resumeRestoredRun(hostReference: fixture.host) }
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.failureGate.open()
        await fixture.store.waitForLoadCount(2)
        await fixture.firstProbeGate.open()
        await fixture.store.waitForLoadCount(3)
        await fixture.store.replaceState(makeState([fixture.completed]))
        await fixture.fenceProbeGate.open()

        let result = try await resume.value
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        let counts = await fixture.adapter.counts()

        #expect(result == RuntimeResult(runReference: fixture.run, outcome: .completed, artifactReferences: []))
        #expect(await fixture.plane.projection(for: fixture.host) == .completed)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        #expect(counts.stream == 1)
        #expect(counts.terminalResult == 0)
    }

    /// VOY-747-review_claim_conflict: resume claim CAS conflict adopts a same-run persisted terminal.
    /// 복원 preflight와 claim 저장 사이에 다른 control plane이 저장한 같은 run terminal로 수렴하는지 검증한다.
    /// - 검증 내용: completed 결과, exact restored owner 종료, persisted terminal 채택, provider 미호출.
    /// - 사전 조건: restore claim 획득 뒤 resume claim apply가 같은 run의 completed snapshot과 충돌한다.
    /// - 기대 결과: resume은 completed를 반환하고 lease는 none이 되며 retry restore는 activeRunExists가 아니다.
    @Test
    func `claim conflict adopts same run terminal and finalizes restored owner`() async throws {
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let host: ExternalAgentSessionReference = "review-claim-conflict-host"
        let run = RuntimeRunReference("review-claim-conflict-run")
        let receipt = ProviderInternalSessionReference("review-claim-conflict-receipt")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: receipt,
            runReference: run,
            projection: .running,
        )
        let completed = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: receipt,
            runReference: run,
            projection: .completed,
        )
        let store = DeterministicHostMutationRuntimeStateStore(
            state: makeState([stored]),
            conflictingUpdateStates: [2: makeState([completed])],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let result = try await plane.resumeRestoredRun(hostReference: host)

        let persisted = try #require(await store.currentState()?.sessions.first)
        let counts = await adapter.counts()
        let restartBindings = await adapter.receivedRestartBindings()
        #expect(result == RuntimeResult(runReference: run, outcome: .completed, artifactReferences: []))
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .stale)
        #expect(restartBindings.count == 1)
        #expect(counts.stream == 0)
        #expect(counts.terminalResult == 0)
        #expect(await store.updateCount == 2)
    }
}

private struct ReviewP1FourFixture {
    let firstProbeGate: RuntimeTestGate
    let fenceProbeGate: RuntimeTestGate
    let failureGate: RuntimeTestGate
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let completed: RuntimeStoredSession
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

private func makeReviewP1FourFixture() -> ReviewP1FourFixture {
    let firstProbeGate = RuntimeTestGate()
    let fenceProbeGate = RuntimeTestGate()
    let failureGate = RuntimeTestGate()
    let host: ExternalAgentSessionReference = "review-p1-4-host"
    let run = RuntimeRunReference("review-p1-4-run")
    let context = makeContext()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("review-p1-4-receipt"),
        runReference: run,
        projection: .running,
    )
    let completed = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("review-p1-4-receipt"),
        runReference: run,
        projection: .completed,
    )
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        loadErrors: [2: .unavailable],
        loadGates: [2: firstProbeGate, 3: fenceProbeGate],
    )
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: .allSupported,
        eventStreamRuntimeFailure: RuntimeAdapterFailure(
            kind: .processExit,
            diagnosticCode: RuntimeDiagnosticCode("process_exit"),
        ),
        eventStreamRuntimeFailureGate: failureGate,
    )
    return ReviewP1FourFixture(
        firstProbeGate: firstProbeGate,
        fenceProbeGate: fenceProbeGate,
        failureGate: failureGate,
        host: host,
        run: run,
        context: context,
        completed: completed,
        store: store,
        adapter: adapter,
        plane: RuntimeControlPlane(store: store),
    )
}

private enum ReviewAdapterInterruption: String, CaseIterable {
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

private enum ReviewTerminalProbeScenario: String, CaseIterable {
    case processExitInvalidPersistedState
    case processExitUnsupportedSchemaVersion
    case transportLossInvalidPersistedState
    case transportLossUnsupportedSchemaVersion

    var interruption: ReviewAdapterInterruption {
        switch self {
        case .processExitInvalidPersistedState, .processExitUnsupportedSchemaVersion:
            .processExit
        case .transportLossInvalidPersistedState, .transportLossUnsupportedSchemaVersion:
            .transportLoss
        }
    }

    var storeError: RuntimeStateStoreError {
        switch self {
        case .processExitInvalidPersistedState, .transportLossInvalidPersistedState:
            .invalidSnapshot
        case .processExitUnsupportedSchemaVersion, .transportLossUnsupportedSchemaVersion:
            .unsupportedSchemaVersion(999)
        }
    }

    var hostError: RuntimeHostError {
        switch self {
        case .processExitInvalidPersistedState, .transportLossInvalidPersistedState:
            .invalidPersistedState
        case .processExitUnsupportedSchemaVersion, .transportLossUnsupportedSchemaVersion:
            .unsupportedSchemaVersion(999)
        }
    }
}

private func reviewStreamOnlyCapabilities() -> RuntimeCapabilities {
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

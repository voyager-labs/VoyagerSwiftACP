import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-post_claim_review

    /// VOY-747-post_claim_terminal: claim 성공 뒤 queued host terminal이 provider 호출보다 먼저 수렴한다.
    /// resume claim 저장과 같은 host terminal 저장이 직렬화되는 경계에서 provider 소비를 시작하지 않는지 검증한다.
    /// - 검증 내용: completed 결과, exact resuming owner 종료, durable claim 제거, provider 미호출.
    /// - 사전 조건: resume claim apply가 gate에서 대기하는 동안 같은 plane의 host completed event를 queue한다.
    /// - 기대 결과: queued terminal 저장을 관찰한 resume은 provider 호출 없이 completed를 반환한다.
    @Test
    func `post claim host terminal returns before provider consumption`() async throws {
        let gate = RuntimeTestGate()
        let host: ExternalAgentSessionReference = "post-claim-terminal-host"
        let run = RuntimeRunReference("post-claim-terminal-run")
        let context = makeContext()
        let stored = postClaimStoredSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            saveGates: [2: gate],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await store.waitForSaveCount(2)
        let terminalTask = Task {
            try await plane.ingestHostEvent(postClaimTerminalEvent(host: host, run: run))
        }
        while await plane.pendingPersistenceMutations[host, default: 0] < 2 {
            await Task.yield()
        }
        await gate.open()

        let result = try await resume.value
        _ = try await terminalTask.value
        let persisted = try #require(await store.currentState()?.sessions.first)
        let counts = await adapter.counts()

        #expect(result == RuntimeResult(runReference: run, outcome: .completed, artifactReferences: []))
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        #expect(counts.stream == 0)
        #expect(counts.terminalResult == 0)
    }

    /// VOY-747-post_claim_cancel: persistence gate에서 취소된 resume은 provider 호출 전에 claim을 복구한다.
    /// resume claim과 queued host event가 직렬화되는 동안 caller cancellation을 관찰하는 경계를 검증한다.
    /// - 검증 내용: exact CancellationError, restored owner 복구, durable claim 유지, provider 미호출.
    /// - 사전 조건: resume claim apply가 gate에서 대기하고 같은 host progress event가 persistence lock을 기다린다.
    /// - 기대 결과: gate 해제 뒤 취소가 우선하며 provider를 호출하지 않고 exact restored lease로 돌아간다.
    @Test
    func `post claim persistence gate cancellation avoids provider consumption`() async throws {
        let gate = RuntimeTestGate()
        let host: ExternalAgentSessionReference = "post-claim-cancel-host"
        let run = RuntimeRunReference("post-claim-cancel-run")
        let context = makeContext()
        let stored = postClaimStoredSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            saveGates: [2: gate],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await store.waitForSaveCount(2)
        let eventTask = Task {
            try await plane.ingestHostEvent(postClaimProgressEvent(host: host, run: run))
        }
        while await plane.pendingPersistenceMutations[host, default: 0] < 2 {
            await Task.yield()
        }
        resume.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await resume.value }
        _ = try await eventTask.value
        let persisted = try #require(await store.currentState()?.sessions.first)
        let counts = await adapter.counts()

        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(persisted.restorationClaim != nil)
        #expect(counts.stream == 0)
        #expect(counts.terminalResult == 0)
    }

    /// VOY-747-post_claim_cancel: restore claim commit 중 취소된 caller는 claim을 소유하지 않는다.
    /// cancellation-neutral store apply가 끝난 직후 취소를 관찰하고 방금 발급한 exact claim만 회수하는 경계를 검증한다.
    /// - 검증 내용: CancellationError, durable claim 제거, inactive lease, provider 미호출과 즉시 재시도.
    /// - 사전 조건: restore claim apply가 gate에서 대기하는 동안 caller가 취소된다.
    /// - 기대 결과: 취소된 restore는 `.restored`를 반환하지 않고 후속 restore가 즉시 claim을 획득한다.
    @Test
    func `post-commit cancelled restore clears only its exact claim`() async throws {
        let gate = RuntimeTestGate()
        let host: ExternalAgentSessionReference = "post-claim-restore-cancel-host"
        let run = RuntimeRunReference("post-claim-restore-cancel-run")
        let context = makeContext()
        let stored = postClaimStoredSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            saveGates: [1: gate],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let restore = Task { try await plane.restore(hostReference: host, expectedContext: context) }
        await store.waitForSaveCount(1)
        restore.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await restore.value }
        let persistedAfterCancellation = try #require(await store.currentState()?.sessions.first)
        #expect(persistedAfterCancellation.restorationClaim == nil)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await adapter.counts().stream == 0)
        #expect(await adapter.counts().terminalResult == 0)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        try await assertPostCommitCancellationCleanupPersistenceFailure()
    }

    /// VOY-747-nested_fence_error: expired claim clear 충돌 뒤 두 번째 fencing load의 typed 오류를 보존한다.
    /// process/transport interruption cleanup의 nested persisted read가 손상/schema 오류를 반환하는 경계를 검증한다.
    /// - 검증 내용: exact typed 오류, exact local owner 비활성화, cleanup evidence, bounded store/provider 호출.
    /// - 사전 조건: claim 만료 뒤 clear apply #3은 충돌하고 fencing load #4는 typed 오류를 반환한다.
    /// - 기대 결과: adapter interruption 대신 typed persisted 오류가 반환되고 stale resuming owner는 남지 않는다.
    @Test(arguments: PostClaimTypedFencingScenario.allCases)
    private func `nested fencing errors preserve typed persistence taxonomy`(
        scenario: PostClaimTypedFencingScenario,
    ) async throws {
        let fixture = postClaimTypedFencingFixture(scenario)
        try await fixture.plane.register(fixture.adapter)

        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let resume = Task { try await fixture.plane.resumeRestoredRun(hostReference: fixture.host) }
        await fixture.adapter.waitForEventStreamCount(1)
        fixture.clock.advance(by: 60)
        await fixture.failureGate.open()

        await #expect(throws: scenario.hostError) { try await resume.value }
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        #expect(await fixture.store.applyCount == 3)
        #expect(await fixture.store.loadCount == 4)
        #expect(persisted.restorationClaim != nil)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.plane.cleanupFailureEvidence(for: fixture.host) == RuntimeCleanupFailureEvidence(
            runReference: fixture.run,
            kind: .persistence,
        ))
        #expect(await fixture.adapter.counts().stream == 1)
        #expect(await fixture.adapter.counts().terminalResult == 0)
    }
}

private func assertPostCommitCancellationCleanupPersistenceFailure() async throws {
    let gate = RuntimeTestGate()
    let host: ExternalAgentSessionReference = "post-claim-cleanup-failure-host"
    let run = RuntimeRunReference("post-claim-cleanup-failure-run")
    let context = makeContext()
    let stored = postClaimStoredSession(host: host, run: run, context: context)
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        failingSaveNumbers: [2],
        saveGates: [1: gate],
    )
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        capabilities: .allSupported,
        eventsByLaunch: [[]],
    )
    let plane = RuntimeControlPlane(store: store)
    try await plane.register(adapter)

    let restore = Task { try await plane.restore(hostReference: host, expectedContext: context) }
    await store.waitForSaveCount(1)
    restore.cancel()
    await gate.open()

    await #expect(throws: CancellationError.self) { try await restore.value }
    let persisted = try #require(await store.currentState()?.sessions.first)
    let local = try #require(await plane.sessions[host])
    #expect(persisted.restorationClaim != nil)
    #expect(local.stored.restorationClaim == persisted.restorationClaim)
    #expect(local.lease == RuntimeControlPlane.RuntimeLease.none)
    #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
        runReference: run,
        kind: .persistence,
    ))
    #expect(await adapter.counts().stream == 0)
    #expect(await adapter.counts().terminalResult == 0)
    #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
}

private struct PostClaimTypedFencingFixture {
    let clock: DeterministicRuntimeRestorationClock
    let failureGate: RuntimeTestGate
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

private enum PostClaimTypedFencingScenario: String, CaseIterable {
    case processExitInvalidPersistedState
    case processExitUnsupportedSchemaVersion
    case transportLossInvalidPersistedState
    case transportLossUnsupportedSchemaVersion

    var interruptionKind: RuntimeAdapterFailureKind {
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

private func postClaimTypedFencingFixture(
    _ scenario: PostClaimTypedFencingScenario,
) -> PostClaimTypedFencingFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let failureGate = RuntimeTestGate()
    let host = ExternalAgentSessionReference("nested-fence-host-\(scenario.rawValue)")
    let run = RuntimeRunReference("nested-fence-run-\(scenario.rawValue)")
    let context = makeContext()
    let capabilities = postClaimStreamOnlyCapabilities()
    let stored = postClaimStoredSession(
        host: host,
        run: run,
        context: context,
        capabilities: capabilities,
    )
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        loadErrors: [4: scenario.storeError],
        conflictingSaveNumbers: [3],
    )
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: capabilities,
        eventStreamRuntimeFailure: RuntimeAdapterFailure(
            kind: scenario.interruptionKind,
            diagnosticCode: RuntimeDiagnosticCode(scenario.rawValue),
        ),
        eventStreamRuntimeFailureGate: failureGate,
    )
    return PostClaimTypedFencingFixture(
        clock: clock,
        failureGate: failureGate,
        host: host,
        run: run,
        context: context,
        store: store,
        adapter: adapter,
        plane: RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        ),
    )
}

private func postClaimStoredSession(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    context: RuntimeContextPolicy,
    capabilities: RuntimeCapabilities = .allSupported,
) -> RuntimeStoredSession {
    makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference("receipt-\(run.rawValue)"),
        runReference: run,
        capabilitySnapshot: capabilities,
        projection: .running,
    )
}

private func postClaimTerminalEvent(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .host,
        providerEventID: ProviderEventID("post-claim-terminal"),
        sequence: 1,
        idempotencyKey: RuntimeIdempotencyKey("post-claim-terminal"),
        timestamp: Date(timeIntervalSince1970: 1),
        externalAgentSessionReference: host,
        runReference: run,
        kind: .completed,
    )
}

private func postClaimProgressEvent(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .host,
        providerEventID: ProviderEventID("post-claim-progress"),
        sequence: 1,
        idempotencyKey: RuntimeIdempotencyKey("post-claim-progress"),
        timestamp: Date(timeIntervalSince1970: 1),
        externalAgentSessionReference: host,
        runReference: run,
        kind: .progress,
    )
}

private func postClaimStreamOnlyCapabilities() -> RuntimeCapabilities {
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

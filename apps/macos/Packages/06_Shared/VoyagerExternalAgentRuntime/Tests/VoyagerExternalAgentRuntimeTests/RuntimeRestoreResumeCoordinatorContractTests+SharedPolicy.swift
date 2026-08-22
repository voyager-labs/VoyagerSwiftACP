import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    /// VOY-747-shared_policy_terminal_precedence: persisted host terminal wins restored provider finish.
    /// 복원 provider finish가 늦게 도착해도 VOY-746 공통 terminal precedence가 host terminal을 보존하는지 검증한다.
    /// - 검증 내용: host terminal 결과, durable projection, claim 제거와 provider 호출 횟수.
    /// - 사전 조건: terminal-only restored provider 결과가 gate에서 대기하고 host interrupted terminal이 먼저 저장된다.
    /// - 기대 결과: provider completed 결과가 terminal을 뒤집지 않고 interrupted 결과로 수렴한다.
    @Test
    func `persisted host terminal wins restored provider finish`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-terminal-host"
        let run = RuntimeRunReference("shared-policy-terminal-run")
        let context = makeContext()
        let resultGate = RuntimeTestGate()
        let capabilities = sharedPolicyTerminalCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("shared-policy-terminal-receipt"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            providerNamespace: "terminal",
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let providerResult = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://provider-finish"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: providerResult,
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(1)

        let hostResult = try await plane.ingestHostEvent(sharedPolicyHostTerminal(
            host: host,
            run: run,
            kind: .interrupted,
        ))
        #expect(hostResult?.outcome == .interrupted)
        await resultGate.open()

        #expect(try await resume.value.outcome == .interrupted)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.projection == .interrupted)
        #expect(persisted.restorationClaim == nil)
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-shared_policy_terminal_lease: same-plane terminal finalizes the restored owner.
    /// terminal-only 복원 소비가 이미 저장된 같은 plane의 terminal을 반환할 때 resuming lease까지 정리하는지 검증한다.
    /// - 검증 내용: returned terminal, durable projection, inactive lease와 provider 호출 횟수.
    /// - 사전 조건: terminal-only provider 결과가 gate에서 대기하고 같은 plane이 host terminal을 먼저 저장한다.
    /// - 기대 결과: resume은 host terminal을 반환하고 session lease는 none으로 종료된다.
    @Test
    func `same-plane stored terminal clears restored owner`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-same-plane-terminal-host"
        let run = RuntimeRunReference("shared-policy-same-plane-terminal-run")
        let context = makeContext()
        let resultGate = RuntimeTestGate()
        let capabilities = sharedPolicyTerminalCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("same-plane-terminal-receipt"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            providerNamespace: "terminal",
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            terminalResultOverride: RuntimeResult(
                runReference: run,
                outcome: .completed,
                artifactReferences: [],
            ),
            terminalResultGate: resultGate,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(1)

        let terminal = try #require(try await plane.ingestHostEvent(sharedPolicyHostTerminal(
            host: host,
            run: run,
            kind: .interrupted,
        )))
        await resultGate.open()

        #expect(try await resume.value == terminal)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(try await store.currentState()?.sessions.first?.projection == .interrupted)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-shared_policy_process_terminal: durable terminal wins process and transport interruption.
    /// restored provider가 processExit/transportLoss를 반환하기 직전 저장된 host terminal을 우선 채택하는지 검증한다.
    /// - 검증 내용: terminal result, durable projection, inactive lease와 typed provider call 경계.
    /// - 사전 조건: stream failure가 gate에서 대기하고 같은 plane이 completed host terminal을 먼저 저장한다.
    /// - 기대 결과: process/transport 오류 대신 completed terminal을 반환하고 resumption owner를 종료한다.
    @Test(arguments: SharedPolicyResumptionInterruption.allCases)
    private func `durable terminal wins restored process interruption`(
        interruption: SharedPolicyResumptionInterruption,
    ) async throws {
        let host = ExternalAgentSessionReference("shared-policy-interruption-\(interruption.rawValue)")
        let run = RuntimeRunReference("shared-policy-interruption-run-\(interruption.rawValue)")
        let context = makeContext()
        let failureGate = RuntimeTestGate()
        let capabilities = sharedPolicyStreamOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("interruption-receipt"),
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            capabilities: capabilities,
            eventStreamRuntimeFailure: RuntimeAdapterFailure(
                kind: interruption.kind,
                diagnosticCode: RuntimeDiagnosticCode(interruption.rawValue),
            ),
            eventStreamRuntimeFailureGate: failureGate,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        let hostPlane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        let terminal = try #require(try await hostPlane.ingestHostEvent(sharedPolicyHostTerminal(
            host: host,
            run: run,
            kind: .completed,
        )))
        await failureGate.open()

        #expect(try await resume.value == terminal)
        #expect(await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await plane.projection(for: host) == .completed)
        #expect(try await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-shared_policy_cancellation: restored cancellation preserves the exact claim and CancellationError.
    /// 복원 caller 취소가 VOY-746 취소 분류를 유지하면서 claim owner/expiry를 바꾸지 않는지 검증한다.
    /// - 검증 내용: CancellationError, exact persisted claim, running projection과 provider 호출 횟수.
    /// - 사전 조건: restored stream이 gate에서 대기하고 resume 후 claim snapshot을 별도로 보존한다.
    /// - 기대 결과: 취소 뒤 동일 claim이 persisted/local 상태에 남고 provider terminal은 호출되지 않는다.
    @Test
    func `restored cancellation preserves claim and CancellationError`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-cancel-host"
        let run = RuntimeRunReference("shared-policy-cancel-run")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let capabilities = sharedPolicyStreamOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("shared-policy-cancel-receipt"),
            runReference: run,
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        let claimed = try #require(await store.currentState()?.sessions.first)
        resume.cancel()
        await streamGate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await resume.value
        }
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted == claimed)
        #expect(await plane.sessions[host]?.stored == claimed)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-shared_policy_terminal_cas: restored terminal second CAS conflict remains persistenceConflict.
    /// 복원 terminal result가 VOY-746 bounded repair를 한 번만 수행하고 두 번째 conflict를 read-only로 끝내는지 검증한다.
    /// - 검증 내용: persistenceConflict, apply 상한, running claim과 provider 호출 횟수.
    /// - 사전 조건: restored terminal-only result의 최초/repair apply가 모두 CAS conflict한다.
    /// - 기대 결과: 추가 write나 provider 재호출 없이 persistenceConflict와 원래 claim이 유지된다.
    @Test
    func `restored terminal second CAS conflict remains persistenceConflict`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-cas-host"
        let run = RuntimeRunReference("shared-policy-cas-run")
        let context = makeContext()
        let capabilities = sharedPolicyTerminalCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("shared-policy-cas-receipt"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            providerNamespace: "terminal",
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            eventsByLaunch: [[]],
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            conflictingSaveNumbers: [3, 4],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForTerminalResultCount(1)
        let claimed = try #require(await store.currentState()?.sessions.first)
        await #expect(throws: RuntimeHostError.persistenceConflict) {
            _ = try await resume.value
        }

        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(await store.applyCount == 4)
        #expect(await store.loadCount == 3)
        #expect(persisted == claimed)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await adapter.counts().terminalResult == 1)
    }

    /// VOY-747-shared_policy_cleanup: cleanup failure keeps terminal and primary error.
    /// 복원 provider 오류의 cleanup 저장 실패가 redacted evidence만 남기고 primary adapter 오류를 가리지 않는지 검증한다.
    /// - 검증 내용: adapterUnavailable, host terminal, bounded cleanup evidence와 provider call 횟수.
    /// - 사전 조건: restored stream이 대기하고 host terminal이 저장된 뒤 cleanup apply만 실패한다.
    /// - 기대 결과: durable terminal은 유지되고 primary 오류가 그대로 반환되며 evidence에는 run taxonomy만 남는다.
    @Test
    func `cleanup failure keeps terminal and primary error`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-cleanup-host"
        let run = RuntimeRunReference("shared-policy-cleanup-run")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("shared-policy-cleanup-receipt"),
            runReference: run,
            projection: .running,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: .creation,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: .unavailable],
            failingSaveNumbers: [4],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        #expect(try await plane.ingestHostEvent(sharedPolicyHostTerminal(
            host: host,
            run: run,
            kind: .completed,
        ))?.outcome == .completed)
        await streamGate.open()

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await resume.value
        }
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.projection == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
            runReference: run,
            kind: .persistence,
        ))
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }

    /// VOY-747-shared_policy_schema_probe: probe schema failure restores the exact claim.
    /// heartbeat terminal probe의 schema 오류가 typed taxonomy를 유지하면서 복원 claim을 바꾸지 않는지 검증한다.
    /// - 검증 내용: unsupportedSchemaVersion, exact claim, running projection과 bounded provider 호출.
    /// - 사전 조건: heartbeat CAS conflict 뒤 persisted terminal probe load에 미래 schema 오류를 주입한다.
    /// - 기대 결과: schema 오류는 보존되고 local lease만 restored로 되돌아가며 claim owner/expiry는 동일하다.
    @Test
    func `probe schema failure restores exact claim`() async throws {
        let host: ExternalAgentSessionReference = "shared-policy-schema-host"
        let run = RuntimeRunReference("shared-policy-schema-run")
        let context = makeContext()
        let now = Date(timeIntervalSince1970: 4_102_444_800)
        let clock = DeterministicRuntimeRestorationClock(currentDate: now)
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("shared-policy-schema-receipt"),
            runReference: run,
            projection: .running,
        )
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: .creation,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            loadErrors: [2: .unsupportedSchemaVersion(999)],
            conflictingSaveNumbers: [3],
        )
        let plane = RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(1),
            restorationClock: clock.runtimeClock,
        )
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let claimed = try #require(await store.currentState()?.sessions.first)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        await clock.waitUntilSleeping()
        await clock.releaseSleepers()
        await store.waitForLoadCount(2)
        await streamGate.open()

        await #expect(throws: RuntimeHostError.unsupportedSchemaVersion(999)) {
            _ = try await resume.value
        }
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(await store.applyCount == 3)
        #expect(await store.loadCount == 2)
        #expect(persisted == claimed)
        #expect(await plane.sessions[host]?.stored == claimed)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().terminalResult == 0)
    }
}

private enum SharedPolicyResumptionInterruption: String, CaseIterable {
    case processExit
    case transportLoss

    var kind: RuntimeAdapterFailureKind {
        switch self {
        case .processExit: .processExit
        case .transportLoss: .transportLoss
        }
    }
}

private func sharedPolicyTerminalCapabilities() -> RuntimeCapabilities {
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

private func sharedPolicyStreamOnlyCapabilities() -> RuntimeCapabilities {
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

private func sharedPolicyHostTerminal(
    host: ExternalAgentSessionReference,
    run: RuntimeRunReference,
    kind: RuntimeEventKind,
) -> RuntimeEventEnvelope {
    RuntimeEventEnvelope(
        source: .host,
        providerEventID: ProviderEventID("shared-policy-host-terminal"),
        sequence: 1,
        idempotencyKey: RuntimeIdempotencyKey("shared-policy-host-terminal"),
        timestamp: Date(timeIntervalSince1970: 1),
        externalAgentSessionReference: host,
        runReference: run,
        kind: kind,
    )
}

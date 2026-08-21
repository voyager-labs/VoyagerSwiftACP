import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    /// VOY-747-restore_resume_ownership: restoration heartbeat does not swallow cancellation when terminal is visible.
    /// resume caller 취소를 이미 보이는 terminal 결과의 성공으로 변환하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파와 durable completed projection 보존.
    /// - 사전 조건: 복원 provider stream이 대기하는 동안 같은 plane이 host terminal을 저장한다.
    /// - 기대 결과: resume caller는 취소되고 terminal snapshot은 completed 상태로 남는다.
    @Test
    func `restoration heartbeat does not swallow cancellation when terminal is visible`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = ExternalAgentSessionReference("host-heartbeat-cancellation")
        let run = RuntimeRunReference("run-heartbeat-cancellation")
        let context = makeContext()
        let streamGate = RuntimeTestGate()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-cancellation"),
            runReference: run,
            projection: .running,
        )
        let store = RuntimeFileStateStore(fileURL: fileURL)
        try await store.seed(makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await plane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)
        _ = try await plane.ingestHostEvent(ownershipMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))

        resume.cancel()

        await #expect(throws: CancellationError.self) { try await resume.value }
        #expect(await plane.projection(for: host) == .completed)
        #expect(try await store.load()?.sessions.first?.projection == .completed)
        await streamGate.open()
    }

    /// VOY-747-restore_resume_ownership: restored terminal result retries transient persistence failure.
    /// 복원 소비가 얻은 terminal 결과를 interruption으로 바꾸지 않고 동일 결과 저장만 재시도하는지 검증한다.
    /// - 검증 내용: 첫 finish save 실패 뒤 반환 결과, durable projection, artifact와 save 횟수.
    /// - 사전 조건: terminal-only restored run과 첫 save만 실패하는 state store가 있다.
    /// - 기대 결과: resume은 persistenceFailure를 반환하고 claim을 보존한 채 재시도 가능한 상태가 된다.
    @Test
    func `restored terminal result retries transient persistence failure`() async throws {
        let host = ExternalAgentSessionReference("host-resume-finish-retry")
        let run = RuntimeRunReference("run-resume-finish-retry")
        let context = makeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://restored-finish-retry.json"],
        )
        let capabilities = ownershipTerminalOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-finish-retry"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            providerNamespace: "terminal",
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            failingSaveNumbers: [2],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: expected,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.saveCount == 2)
    }

    /// VOY-747-restore_resume_ownership: failed restored terminal persistence restores its claim.
    /// terminal 결과 저장이 실패해도 복원 claim을 잃지 않고 같은 control plane에서 다시 재개할 수 있는지 검증한다.
    /// - 검증 내용: persistenceFailure 전파, running projection 보존, claim owner와 save 횟수.
    /// - 사전 조건: terminal-only restored run과 terminal 저장 실패를 주입한 state store가 있다.
    /// - 기대 결과: 첫 resume 뒤 claim이 복구되어 동일 run을 재시도할 수 있다.
    @Test
    func `failed restored terminal persistence restores its claim`() async throws {
        let host = ExternalAgentSessionReference("host-resume-finish-double-failure")
        let run = RuntimeRunReference("run-resume-finish-double-failure")
        let context = makeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://restored-finish-double-failure.json"],
        )
        let capabilities = ownershipTerminalOnlyCapabilities()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-finish-double-failure"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            providerNamespace: "terminal",
            capabilitySnapshot: capabilities,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            failingSaveNumbers: [2],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: expected,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        let ownerToken = await plane.restorationOwnerToken
        #expect(await store.currentState()?.sessions.first?.restorationClaim?.ownerToken == ownerToken)
        #expect(await store.saveCount == 2)
    }

    /// VOY-747-restore_resume_ownership: cancelled restored consumption preserves its claim.
    /// caller task 취소가 provider interruption으로 저장되지 않고 동일 run의 재개 가능성을 유지하는지 검증한다.
    /// - 검증 내용: 두 번의 CancellationError 전파, running projection 보존, 두 번째 stream 재개.
    /// - 사전 조건: compatible running snapshot과 지연된 provider event stream이 있다.
    /// - 기대 결과: 두 번의 caller cancellation 모두 durable interruption 없이 원래 취소로 종료된다.
    @Test
    func `cancelled restored consumption preserves its claim`() async throws {
        let host = ExternalAgentSessionReference("host-resume-cancelled")
        let run = RuntimeRunReference("run-resume-cancelled")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-cancelled"),
            runReference: run,
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([stored]))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        for expectedStreamCount in 1 ... 2 {
            let task = Task { try await plane.resumeRestoredRun(hostReference: host) }
            await adapter.waitForEventStreamCount(expectedStreamCount)
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await plane.projection(for: host) == .running)
            #expect(await store.currentState()?.sessions.first?.projection == .running)
            #expect(await store.currentState()?.sessions.first?.restorationClaim != nil)
        }
    }

    /// VOY-747-restore_resume_ownership: restored run remains retryable after cleanup persistence failures.
    /// 복원 소비의 terminal 저장과 interruption 저장이 연속 실패해도 lease를 다시 소비할 수 있는지 검증한다.
    /// - 검증 내용: persistence failure 뒤 동일 restored run의 provider stream 재개와 claim 보존.
    /// - 사전 조건: compatible running snapshot과 첫 persistence mutation 실패를 주입한 state store가 있다.
    /// - 기대 결과: 첫 resume은 persistenceFailure이고 run은 retry 가능한 running claim으로 남는다.
    @Test
    func `restored run remains retryable after cleanup persistence failures`() async throws {
        let host = ExternalAgentSessionReference("host-resume-retry")
        let run = RuntimeRunReference("run-resume-retry")
        let context = makeContext()
        let stored = makeEqualitySession(
            storedContext: RuntimeStoredContext(contextPolicy: context),
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-retry"),
            runReference: run,
            projection: .running,
        )
        let completed = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "retry-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[completed]],
        )
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            failingSaveNumbers: [2],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await plane.sessions[host]?.lease.isAwaitingResumption == true)
        #expect(await store.currentState()?.sessions.first?.restorationClaim != nil)
        #expect(await adapter.counts().stream == 0)
    }

    /// VOY-747-restore_resume_ownership: failed concurrent persistence cannot resurrect resume claim.
    /// 다른 host 저장 실패가 진행 중인 복원 소비 claim을 되살려 중복 stream을 여는 경쟁을 차단한다.
    /// - 검증 내용: persistence lock 대기, 실패 rollback 뒤 claim 상태, 두 번째 resume 거부, stream 호출 횟수.
    /// - 사전 조건: 복원 claim을 가진 running session과 save 실패 gate, 소비 stream gate가 구성되어 있다.
    /// - 기대 결과: claim은 persistence mutation과 직렬화되고 provider stream은 한 번만 열린다.
    @Test
    func `failed concurrent persistence cannot resurrect resume claim`() async throws {
        let fixture = try await ownershipMakeResumeClaimRace()

        let competingSave = Task {
            try await fixture.plane.projectPrelaunch(
                makeLaunch(
                    host: "host-competing-save",
                    run: RuntimeRunReference("run-competing-save"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }
        await fixture.store.waitForSaveCount(2)
        let firstResume = Task {
            try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        }
        let boundary = try await ownershipWaitForResumeClaimBoundary(
            host: fixture.host,
            on: fixture.plane,
        )

        #expect(boundary.awaitingResumption)
        #expect(boundary.persistenceWaiterCount == 1)
        await fixture.saveGate.open()
        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await competingSave.value
        }
        await fixture.adapter.waitForEventStreamCount(1)
        let awaitingResumption = await fixture.plane.sessions[fixture.host]?.lease.isAwaitingResumption
        #expect(awaitingResumption == false)
        if awaitingResumption == false {
            await #expect(throws: RuntimeHostError.invalidEvent) {
                try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
            }
        }
        await fixture.streamGate.open()

        #expect(try await firstResume.value.outcome == .completed)
        #expect(await fixture.adapter.counts().stream == 1)
    }

    /// VOY-747-restore_resume_ownership: cancelled restore persistence waiter cannot mint a claim.
    /// persistence lock을 기다리다 취소된 restore가 소유자 없는 restored lease를 발급하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, inactive lease 보존, 같은 control plane의 restore 재시도.
    /// - 사전 조건: compatible running snapshot과 다른 host의 지연된 persistence mutation이 있다.
    /// - 기대 결과: 취소된 waiter는 claim을 만들지 않고 후속 restore가 restored 결과를 반환한다.
    @Test
    func `cancelled restore persistence waiter cannot mint a claim`() async throws {
        let host = ExternalAgentSessionReference("host-restore-waiter-cancelled")
        let run = RuntimeRunReference("run-restore-waiter-cancelled")
        let context = makeContext()
        let saveGate = RuntimeTestGate()
        let stored = ownershipMakeRunningSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: makeState([stored]),
            saveGates: [1: saveGate],
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let competingSave = Task {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: "host-restore-waiter-competing-save",
                    run: RuntimeRunReference("run-restore-waiter-competing-save"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }
        await store.waitForSaveCount(1)
        let restore = Task {
            try await plane.restore(hostReference: host, expectedContext: context)
        }
        try await ownershipWaitForPersistenceWaiters(1, on: plane)

        restore.cancel()
        await saveGate.open()

        _ = try await competingSave.value
        await #expect(throws: CancellationError.self) { try await restore.value }
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
    }

    /// VOY-747-restore_resume_ownership: cancelled resume persistence waiter cannot mint a claim.
    /// persistence lock을 기다리다 취소된 resume이 소유자 없는 resuming lease나 provider stream을 만들지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, restored lease 보존, stream 미호출, 같은 control plane의 resume 재시도.
    /// - 사전 조건: restored claim과 다른 host의 지연된 persistence mutation, 소비 stream gate가 있다.
    /// - 기대 결과: 취소된 waiter는 claim을 전환하지 않고 후속 resume만 provider stream을 한 번 연다.
    @Test
    func `cancelled resume persistence waiter cannot mint a claim`() async throws {
        let fixture = try await ownershipMakeResumeClaimRace()
        let restoredLease = await fixture.plane.sessions[fixture.host]?.lease
        let competingSave = Task {
            try await fixture.plane.projectPrelaunch(
                makeLaunch(
                    host: "host-resume-waiter-competing-save",
                    run: RuntimeRunReference("run-resume-waiter-competing-save"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }
        await fixture.store.waitForSaveCount(2)
        let resume = Task {
            try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        }
        try await ownershipWaitForPersistenceWaiters(1, on: fixture.plane)

        resume.cancel()
        await fixture.saveGate.open()

        _ = try? await competingSave.value
        _ = try? await resume.value
        #expect(await fixture.adapter.counts().stream == 0)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == restoredLease)

        let retry = Task {
            try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        }
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.streamGate.open()

        #expect(try await retry.value.outcome == .completed)
        #expect(await fixture.adapter.counts().stream == 1)
    }
}

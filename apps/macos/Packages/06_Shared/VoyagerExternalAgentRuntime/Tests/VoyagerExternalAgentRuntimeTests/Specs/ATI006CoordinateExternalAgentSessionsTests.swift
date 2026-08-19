import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("ATI-006 Coordinate External Agent Sessions")
struct ATI006CoordinateExternalAgentSessionsTests {
    enum PersistenceBoundaryFailure: String, CaseIterable {
        case conflict
        case unavailable
    }

    enum HeartbeatProbeFailure: String, CaseIterable {
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

    enum CommittedSnapshotFailure: String, CaseIterable {
        case duplicateHosts
        case futureSchema
        case invalidBounds
        case missingProviderReference

        var hostError: RuntimeHostError {
            switch self {
            case .futureSchema:
                .unsupportedSchemaVersion(RuntimeStoredState.currentSchemaVersion + 1)
            case .duplicateHosts, .invalidBounds, .missingProviderReference:
                .invalidPersistedState
            }
        }
    }

    enum OperationCancellationCase: String {
        case approval
        case queuedInput
        case cancellation

        func invocationCount(in adapter: DeterministicRuntimeAdapter) async -> Int {
            let counts = await adapter.counts()
            switch self {
            case .approval:
                return counts.approval
            case .queuedInput:
                return counts.input
            case .cancellation:
                return counts.cancellation
            }
        }
    }

    // MARK: - ATI-006-coordinate_external_agent_launch

    /// ATI-006-coordinate_external_agent_launch: receipt persistence distinguishes a conflict from unavailable storage.
    /// 실제 run 경로에서 provider receipt 저장 실패와 started-provider cleanup 상태를 검증한다.
    /// - 검증 내용: `RuntimeControlPlane.run`의 receipt commit, conflict/unavailable 오류, provider binding과 interrupted
    /// cleanup.
    /// - 사전 조건: policy-ready prelaunch와 deterministic provider가 구성되고 receipt 저장 시점에 경계 실패가 주입된다.
    /// - 기대 결과: 두 실패 모두 provider를 재실행하지 않으며 cleanup은 provider handle을 보존한 interrupted 상태로 수렴한다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `receipt persistence distinguishes conflict from unavailable storage`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-receipt-boundary-\(failure.rawValue)")
        let run = RuntimeRunReference("run-receipt-boundary-\(failure.rawValue)")
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: failure == .unavailable ? [3] : [],
            conflictingSaveNumbers: failure == .conflict ? [3] : [],
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        if failure == .conflict {
            await #expect(throws: RuntimeHostError.persistenceConflict) { _ = try await plane.run(request) }
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) { _ = try await plane.run(request) }
        }
        #expect(await adapter.counts().launch == 1)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.projection == .interrupted)
        #expect(persisted.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
    }

    // MARK: - ATI-006-coordinate_external_agent_launch

    /// ATI-006-coordinate_external_agent_launch: receipt conflict followed by unavailable cleanup reports persistence
    /// failure.
    /// receipt commit conflict 뒤 cleanup 저장소가 unavailable이면 cleanup 오류가 원래 conflict보다 우선하는지 검증한다.
    /// - 검증 내용: save #3 receipt conflict, save #4 cleanup unavailable, exact error, running claim과 retry 차단.
    /// - 사전 조건: policy-ready prelaunch와 receipt를 반환하는 provider가 구성되고 두 저장 경계 오류가 순서대로 주입된다.
    /// - 기대 결과: `persistenceFailure`를 반환하고 provider-started running 상태와 durable handle을 보존한다.
    @Test
    func `receipt conflict followed by unavailable cleanup reports persistence failure`() async throws {
        let host = ExternalAgentSessionReference("host-receipt-conflict-cleanup-unavailable")
        let run = RuntimeRunReference("run-receipt-conflict-cleanup-unavailable")
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: [4],
            conflictingSaveNumbers: [3],
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await plane.run(request)
        }
        #expect(await store.saveCount == 4)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await plane.run(request)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: launch cleanup keeps provider-started state fail-closed.
    /// receipt 이후 cleanup 저장 경계에서 conflict와 unavailable을 구분하고 provider side effect를 보존한다.
    /// - 검증 내용: provider launch 실패 후 started-provider interruption cleanup과 재실행 차단.
    /// - 사전 조건: provider가 receipt를 반환한 뒤 소비 stream 생성이 실패하고 cleanup 저장 경계가 주입된다.
    /// - 기대 결과: conflict는 durable terminal을 채택하고 unavailable은 persistenceFailure와 running owner를 보존한다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `launch cleanup keeps provider-started state fail-closed`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-launch-cleanup-\(failure.rawValue)")
        let run = RuntimeRunReference("run-launch-cleanup-\(failure.rawValue)")
        let context = finalReviewTestsMakeContext()
        let terminal = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .completed,
            providerLaunchAttempted: true,
        )
        let terminalState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [terminal],
        )
        let store = DeterministicHostMutationRuntimeStateStore(
            failingUpdateNumbers: failure == .unavailable ? [4] : [],
            conflictingUpdateStates: failure == .conflict ? [4: terminalState] : [:],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamFailure: .creation,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        if failure == .conflict {
            #expect(try await runPolicyReady(plane, request).outcome == .completed)
            #expect(await plane.projection(for: host) == .completed)
            #expect(await plane.sessions[host]?.lease.isActive == false)
            #expect(await store.currentState()?.sessions == [terminal])
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) {
                _ = try await runPolicyReady(plane, request)
            }
            #expect(await plane.projection(for: host) == .running)
            #expect(await plane.sessions[host]?.lease.isActive == true)
            #expect(await store.currentState()?.sessions.first?.projection == .running)
        }
        #expect(await adapter.counts().launch == 1)
        #expect(await store.currentState()?.sessions.first?.providerLaunchAttempted == true)
        #expect(await store.updateCount == 4)
    }

    /// ATI-006-coordinate_external_agent_launch: receipt persistence cancellation detaches the launch owner.
    /// Provider receipt 이후 저장 중 caller가 취소되어도 started provider ownership을 정리 가능한 상태로 남기는지 검증한다.
    /// - 검증 내용: caller cancellation, receipt를 포함한 interruption cleanup, exact launch lease 해제, provider 중복 실행 방지.
    /// - 사전 조건: receipt 저장인 세 번째 save가 cancellation-aware delay에서 대기한다.
    /// - 기대 결과: caller는 CancellationError를 받고 detached owner는 후속 terminal evidence에서 정확히 해제된다.
    @Test
    func `receipt persistence cancellation detaches the launch owner`() async throws {
        let host: ExternalAgentSessionReference = "host-receipt-cancellation"
        let run = RuntimeRunReference("run-receipt-cancellation")
        let store = InMemoryRuntimeStateStore(saveDelays: [3: .seconds(2)])
        let adapter = DeterministicRuntimeAdapter(id: "sdk")
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")

        try await plane.projectPrelaunch(request, as: .policyReady)
        let runTask = Task { try await plane.run(request) }
        await store.waitForSaveCount(3)
        runTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await runTask.value
        }
        #expect(await plane.projection(for: host) == .launching)
        #expect(await plane.sessions[host]?.lease == .detachedLaunching(2))
        #expect(await adapter.counts().launch == 1)
        #expect(await store.saveCount == 3)

        let terminal = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("receipt-cancellation-terminal"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("receipt-cancellation-terminal"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        )
        #expect(try await plane.ingestHostEvent(terminal)?.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(await store.saveCount == 4)
    }

    // MARK: - ATI-006-project_external_agent_run_events

    /// ATI-006-project_external_agent_run_events: terminal event persistence retries only a conflict.
    /// 실제 provider event stream 경로에서 conflict read-repair와 unavailable fail-closed를 검증한다.
    /// - 검증 내용: terminal event commit, retry 횟수, completed projection과 result metadata.
    /// - 사전 조건: terminal provider event와 deterministic result가 구성되고 event 저장 경계가 주입된다.
    /// - 기대 결과: conflict는 retry 후 completed로 수렴하고 unavailable은 persistenceFailure와 running claim을 남긴다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `terminal event persistence retries only a conflict`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-terminal-event-boundary-\(failure.rawValue)")
        let run = RuntimeRunReference("run-terminal-event-boundary-\(failure.rawValue)")
        let result = RuntimeResult(runReference: run, outcome: .completed, artifactReferences: ["artifact://event"])
        let terminalEventGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: failure == .unavailable ? [4] : [],
            conflictingSaveNumbers: failure == .conflict ? [4] : [],
            saveGates: [4: terminalEventGate],
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
                        idempotencyKey: "terminal",
                        kind: .completed,
                    ),
                ],
            ],
            terminalResultOverride: result,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await store.waitForSaveCount(4)
        #expect(await store.saveCount == 4)
        #expect(await plane.projection(for: host) == .running)
        await terminalEventGate.open()
        if failure == .conflict {
            #expect(try await runTask.value == result)
            #expect(await plane.projection(for: host) == .completed)
            #expect(await store.saveCount == 5)
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) {
                _ = try await runTask.value
            }
            #expect(await plane.projection(for: host) == .interrupted)
            #expect(await store.saveCount == 5)
        }
    }

    /// ATI-006-project_external_agent_run_events: second terminal CAS conflict adopts the durable terminal.
    /// 첫 terminal conflict read-repair 뒤 retry CAS도 충돌하면 최신 동일 run terminal로 다시 수렴하는지 검증한다.
    /// - 검증 내용: 두 번의 host-event CAS conflict, public terminal result, local/durable terminal projection, bounded update
    /// count.
    /// - 사전 조건: 첫 conflict는 running snapshot을, 두 번째 conflict는 동일 host/run completed snapshot을 원자적으로 설치한다.
    /// - 기대 결과: caller는 persistenceConflict 대신 completed 결과를 받고 local registry도 durable terminal과 일치한다.
    @Test
    func `second terminal CAS conflict adopts the durable terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-second-terminal-conflict"
        let run = RuntimeRunReference("run-second-terminal-conflict")
        let running = reviewerBlockerTestsMakeRunningSession(
            host: host,
            run: run,
            context: reviewerBlockerTestsMakeCanonicalContext(),
        )
        let runningState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [running],
        )
        let terminal = running.withProjection(.completed)
        let terminalState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [terminal],
        )
        let store = DeterministicHostMutationRuntimeStateStore(
            state: runningState,
            conflictingUpdateStates: [1: runningState, 2: terminalState],
        )
        let plane = RuntimeControlPlane(store: store)
        let event = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("second-terminal-conflict"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("second-terminal-conflict"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .completed,
        )

        #expect(try await plane.ingestHostEvent(event)?.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(await store.currentState()?.sessions == [terminal])
        #expect(await store.updateCount == 2)
    }

    /// ATI-006-project_external_agent_run_events: stale host terminal conflict adopts the durable terminal.
    /// 다른 control plane이 먼저 저장한 동일 host/run terminal을 stale plane이 event 재적용 없이 반환하는지 검증한다.
    /// - 검증 내용: file-backed conflict read-repair 결과, public terminal outcome, 양쪽 terminal projection.
    /// - 사전 조건: stale plane이 running snapshot을 hydrate한 뒤 다른 plane이 동일 interrupted host event를 저장한다.
    /// - 기대 결과: stale plane의 동일 event ingest도 interrupted를 반환하고 malformedAdapterResponse를 발생시키지 않는다.
    @Test
    func `stale host terminal conflict adopts the durable terminal`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host: ExternalAgentSessionReference = "host-stale-terminal-conflict"
        let run = RuntimeRunReference("run-stale-terminal-conflict")
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: host,
            run: run,
            context: reviewerBlockerTestsMakeCanonicalContext(),
        )
        try await RuntimeFileStateStore(fileURL: fileURL).seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let event = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-stale-terminal-conflict"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-stale-terminal-conflict"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        )
        let stalePlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await stalePlane.hydrateIfNeeded()
        #expect(await stalePlane.projection(for: host) == .running)

        let currentPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        #expect(try await currentPlane.ingestHostEvent(event)?.outcome == .interrupted)

        #expect(try await stalePlane.ingestHostEvent(event)?.outcome == .interrupted)
        #expect(await stalePlane.projection(for: host) == .interrupted)
        #expect(await currentPlane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: conflict read-repair validates loaded lifecycle state.
    /// terminal conflict가 public store의 lifecycle-invalid snapshot을 읽어도 live registry에 설치하지 않는지 검증한다.
    /// - 검증 내용: host terminal CAS conflict, running provider-reference 검증, local registry 원자성.
    /// - 사전 조건: plane은 valid running session을 hydrate했고 store는 동일 run의 provider-reference 없는 snapshot으로 교체된다.
    /// - 기대 결과: invalidPersistedState를 반환하고 기존 running session과 provider binding을 그대로 유지한다.
    @Test
    func `conflict read-repair validates loaded lifecycle state`() async throws {
        let host: ExternalAgentSessionReference = "host-conflict-read-validation"
        let run = RuntimeRunReference("run-conflict-read-validation")
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: host,
            run: run,
            context: reviewerBlockerTestsMakeCanonicalContext(),
        )
        let store = InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState([stored]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.hydrateIfNeeded()
        let malformed = makeEqualitySession(
            storedContext: stored.storedContext,
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            projection: .running,
        )
        await store.replaceState(storageBoundaryTestsMakeState([malformed]))
        let event = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("conflict-read-validation"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("conflict-read-validation"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        )

        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            _ = try await plane.ingestHostEvent(event)
        }
        #expect(await plane.sessions[host]?.stored == stored)
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.saveCount == 1)
    }

    /// ATI-006-project_external_agent_run_events: finish persistence retries only a conflict.
    /// 실제 terminal-only provider 경로에서 finish commit의 conflict retry와 storage fail-closed를 검증한다.
    /// - 검증 내용: finish commit, public result, durable projection, active lease cleanup.
    /// - 사전 조건: terminal-only adapter 결과와 finish 저장 경계가 구성되어 있다.
    /// - 기대 결과: conflict는 completed로 수렴하고 unavailable은 persistenceFailure와 running 상태를 보존한다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `finish persistence retries only a conflict`(failure: PersistenceBoundaryFailure) async throws {
        let host = ExternalAgentSessionReference("host-finish-boundary-\(failure.rawValue)")
        let run = RuntimeRunReference("run-finish-boundary-\(failure.rawValue)")
        let result = RuntimeResult(runReference: run, outcome: .completed, artifactReferences: ["artifact://finish"])
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: failure == .unavailable ? [4] : [],
            conflictingSaveNumbers: failure == .conflict ? [4] : [],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultOverride: result,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        if failure == .conflict {
            #expect(try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "terminal")) == result)
            #expect(await plane.projection(for: host) == .completed)
            #expect(await store.saveCount == 5)
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) {
                _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "terminal"))
            }
            #expect(await plane.projection(for: host) == .running)
            #expect(await store.saveCount == 4)
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: started-provider cleanup preserves replacement safety.
    /// receipt commit 실패 뒤 cleanup owner가 conflict와 unavailable을 구분하는지 검증한다.
    /// - 검증 내용: 실제 run 호출, cleanup conflict retry/read-repair, replacement barrier, provider launch count.
    /// - 사전 조건: receipt와 후속 cleanup 저장 경계에 같은 failure가 주입되고 replacement request가 준비되어 있다.
    /// - 기대 결과: conflict는 receipt-bound interrupted owner로 read-repair되고 replacement가 차단되며,
    /// unavailable은 conflict retry 없이 receipt-bound running owner를 fail-closed로 유지한다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `started-provider cleanup preserves replacement safety`(failure: PersistenceBoundaryFailure) async throws {
        let host = ExternalAgentSessionReference("host-started-cleanup-\(failure.rawValue)")
        let run = RuntimeRunReference("run-started-cleanup-\(failure.rawValue)")
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: failure == .unavailable ? [3, 4] : [],
            conflictingSaveNumbers: failure == .conflict ? [3, 4] : [],
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[], []])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        if failure == .conflict {
            await #expect(throws: RuntimeHostError.persistenceConflict) { _ = try await plane.run(request) }
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) { _ = try await plane.run(request) }
        }
        let replacement = makeLaunch(host: host, run: RuntimeRunReference("replacement"), adapterID: "sdk")
        if failure == .conflict {
            await #expect(throws: RuntimeHostError.activeRunExists) { _ = try await plane.run(replacement) }
            let persisted = try #require(await store.currentState()?.sessions.first)
            #expect(persisted.projection == .interrupted)
            #expect(persisted.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
            #expect(await store.saveCount == 5)
        } else {
            await #expect(throws: RuntimeHostError.activeRunExists) { _ = try await plane.run(replacement) }
            let persisted = try #require(await store.currentState()?.sessions.first)
            #expect(persisted.projection == .launching)
            #expect(persisted.providerInternalSessionReference == nil)
            #expect(await store.saveCount == 4)
        }
        #expect(await adapter.counts().launch == 1)
    }

    // MARK: - ATI-006-coordinate_external_agent_run_continuity

    /// ATI-006-coordinate_external_agent_run_continuity: restore claim distinguishes conflict from unavailable storage.
    /// 실제 restore owner가 conflict를 stale claim으로 처리하고 storage 오류는 fail-closed하는지 검증한다.
    /// - 검증 내용: restoreCompatibility 호출, claim acquisition persistence, stale/failure 결과와 lease 상태.
    /// - 사전 조건: compatible running session과 deterministic adapter가 저장되어 있다.
    /// - 기대 결과: conflict는 stale이며 provider side effect가 없고 unavailable은 persistenceFailure이다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `restore claim distinguishes conflict from unavailable storage`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-restore-claim-\(failure.rawValue)")
        let run = RuntimeRunReference("run-restore-claim-\(failure.rawValue)")
        let context = finalReviewTestsMakeContext()
        let stored = storageBoundaryTestsMakeStored(host: host, run: run)
        let store = InMemoryRuntimeStateStore(
            state: storageBoundaryTestsMakeState([stored]),
            failingSaveNumbers: failure == .unavailable ? [1] : [],
            conflictingSaveNumbers: failure == .conflict ? [1] : [],
        )
        let adapter = storageBoundaryTestsMakeAdapter()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        if failure == .conflict {
            #expect(try await plane.restore(hostReference: host, expectedContext: context) == .stale)
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) {
                _ = try await plane.restore(hostReference: host, expectedContext: context)
            }
        }
        #expect(await adapter.counts().launch == 0)
        #expect(await plane.projection(for: host) == .running)
    }

    // MARK: - ATI-006-coordinate_external_agent_launch

    /// ATI-006-coordinate_external_agent_launch: committed store result validates before reconciliation.
    /// public state store가 malformed committed snapshot을 반환해도 live registry에 설치하기 전에 fail-closed하는지 검증한다.
    /// - 검증 내용: future schema, persisted bounds, lifecycle provider-reference 검증과 registry/provider side effect 격리.
    /// - 사전 조건: prelaunch apply가 구조 또는 lifecycle 계약을 위반하는 committed snapshot을 반환한다.
    /// - 기대 결과: typed host error를 반환하고 malformed session을 설치하거나 provider를 launch하지 않는다.
    @Test(arguments: CommittedSnapshotFailure.allCases)
    func `committed store result validates before reconciliation`(
        failure: CommittedSnapshotFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-committed-validation-\(failure.rawValue)")
        let run = RuntimeRunReference("run-committed-validation-\(failure.rawValue)")
        let malformed = makeMalformedCommittedState(failure, host: host, run: run)
        let store = InMemoryRuntimeStateStore(committedSaveStates: [1: malformed])
        let adapter = DeterministicRuntimeAdapter(id: "sdk", eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: failure.hostError) {
            try await plane.projectPrelaunch(
                makeLaunch(host: host, run: run, adapterID: "sdk"),
                as: .policyReady,
            )
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await adapter.counts().launch == 0)
        #expect(await store.saveCount == 1)
    }

    private func makeMalformedCommittedState(
        _ failure: CommittedSnapshotFailure,
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) -> RuntimeStoredState {
        switch failure {
        case .duplicateHosts:
            return storageBoundaryTestsMakeState([
                storageBoundaryTestsMakeStored(host: host, run: run),
                storageBoundaryTestsMakeStored(
                    host: host,
                    run: RuntimeRunReference("\(run.rawValue)-duplicate"),
                ),
            ])
        case .futureSchema:
            return RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion + 1,
                sessions: [],
            )
        case .invalidBounds:
            return storageBoundaryTestsMakeState([
                storageBoundaryTestsMakeStored(host: host, run: run, acceptedEventCount: -1),
            ])
        case .missingProviderReference:
            let stored = storageBoundaryTestsMakeStored(host: host, run: run)
            return storageBoundaryTestsMakeState([
                makeEqualitySession(
                    storedContext: stored.storedContext,
                    externalAgentSessionReference: host,
                    providerInternalSessionReference: nil,
                    runReference: run,
                    projection: .running,
                ),
            ])
        }
    }

    /// ATI-006-coordinate_external_agent_launch: prelaunch persistence is distinct from non-persisting operation
    /// admission.
    /// prelaunch boundary 오류와 pending persistence 중 operation side effect 차단을 별도로 검증한다.
    /// - 검증 내용: projectPrelaunch conflict/unavailable, approval operation의 zero persistence와 pending gate admission.
    /// - 사전 조건: adapter가 approval을 지원하고 prelaunch 저장 경계 또는 다른 persistence mutation이 대기한다.
    /// - 기대 결과: prelaunch는 conflict/storage를 구분하고 operation은 저장하지 않으며 pending mutation 중 provider 호출을 차단한다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `prelaunch persistence and operation admission remain distinct`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-admission-boundary-\(failure.rawValue)")
        let run = RuntimeRunReference("run-admission-boundary-\(failure.rawValue)")
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: failure == .unavailable ? [1] : [],
            conflictingSaveNumbers: failure == .conflict ? [1] : [],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        if failure == .conflict {
            await #expect(throws: RuntimeHostError.persistenceConflict) {
                try await plane.projectPrelaunch(request, as: .policyReady)
            }
        } else {
            await #expect(throws: RuntimeHostError.persistenceFailure) {
                try await plane.projectPrelaunch(request, as: .policyReady)
            }
        }
        #expect(await adapter.counts().launch == 0)
        #expect(await store.saveCount == 1)

        try await assertPendingPersistenceBlocksOperation(request)
    }

    private func assertPendingPersistenceBlocksOperation(_ request: RuntimeLaunchRequest) async throws {
        let persistenceGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [4: persistenceGate])
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        try await plane.projectPrelaunch(request, as: .policyReady)
        let runTask = Task { try await plane.run(request) }
        await adapter.waitForEventStreamCount(1)
        let hostEventTask = Task {
            try await plane.ingestHostEvent(finalReviewTestsMakeHostEvent(
                host: request.externalAgentSessionReference,
                run: request.runReference,
                sequence: 1,
                key: "pending-operation-admission",
            ))
        }
        await store.waitForSaveCount(4)
        let saveCountWhilePending = await store.saveCount
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.respondToApproval(
                hostReference: request.externalAgentSessionReference,
                requestID: RuntimeApprovalRequestID("approval"),
                operationID: RuntimeOperationID("operation"),
            )
        }
        #expect(await adapter.counts().approval == 0)
        #expect(await store.saveCount == saveCountWhilePending)
        await persistenceGate.open()
        _ = try await hostEventTask.value
        await streamGate.open()
        _ = try await runTask.value
        #expect(await store.saveCount > saveCountWhilePending)
    }

    // MARK: - ATI-006-coordinate_external_agent_launch

    // MARK: - ATI-006-project_external_agent_run_events

    // MARK: - ATI-006-coordinate_external_agent_run_continuity

    // MARK: - ATI-006-coordinate_external_agent_launch

    // MARK: - ATI-006-bind_external_agent_session_reference

    /// ATI-006-bind_external_agent_session_reference: distinct host references do not cross-mutate.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `distinct host references do not cross-mutate`() async throws {
        let hostA = ExternalAgentSessionReference("host-a")
        let hostB = ExternalAgentSessionReference("host-b")
        let runA = RuntimeRunReference("run-a")
        let runB = RuntimeRunReference("run-b")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [
                [makeEvent(host: hostA, run: runA, sequence: 1, idempotencyKey: "a", kind: .completed)],
                [makeEvent(host: hostB, run: runB, sequence: 1, idempotencyKey: "b", kind: .completed)],
            ],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        async let resultA = runPolicyReady(plane, makeLaunch(host: hostA, run: runA, adapterID: "sdk"))
        async let resultB = runPolicyReady(plane, makeLaunch(host: hostB, run: runB, adapterID: "sdk"))

        #expect(try await resultA.outcome == .completed)
        #expect(try await resultB.outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    // MARK: - ATI-006-capture_external_agent_context_policy

    /// ATI-006-capture_external_agent_context_policy: policy-ready run completes through deterministic adapter.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `policy-ready run completes through deterministic adapter`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "process",
            transport: .processJSONL,
            eventsByLaunch: [[
                makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "progress", kind: .progress),
                makeEvent(host: host, run: run, sequence: 2, idempotencyKey: "done", kind: .completed),
            ]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "process"))

        #expect(result.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-capture_external_agent_context_policy: launch requires immutable policy ready snapshot.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `launch requires immutable policy ready snapshot`() async throws {
        let adapter = finalBoundaryTestsMakeApprovalAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = makeLaunch(
            host: "host-policy",
            run: RuntimeRunReference("run-policy"),
            adapterID: "sdk",
        )

        await #expect(throws: RuntimeHostError.invalidEvent) { try await plane.run(request) }
        try await plane.projectPrelaunch(request, as: .policyReady)
        let changed = RuntimeLaunchRequest(
            externalAgentSessionReference: request.externalAgentSessionReference,
            runReference: request.runReference,
            adapterID: request.adapterID,
            contextPolicy: RuntimeContextPolicy(
                branchReference: "changed",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
            input: request.input,
        )
        await #expect(throws: RuntimeHostError.invalidEvent) { try await plane.run(changed) }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-capture_external_agent_context_policy: launch rejects policy-ready execution context mutations.
    /// 승인된 실행 컨텍스트 전체가 provider launch 전까지 불변인지 검증한다.
    /// - 검증 내용: working directory, allowed roots, request context 변경 거부.
    /// - 사전 조건: 전체 실행 컨텍스트가 포함된 policy-ready snapshot이 저장되어 있다.
    /// - 기대 결과: 변경된 launch 요청은 거부되고 provider launch 호출은 발생하지 않는다.
    @Test
    func `launch rejects policy-ready execution context mutations`() async throws {
        let adapter = finalBoundaryTestsMakeApprovalAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host-policy-context",
            runReference: RuntimeRunReference("run-policy-context"),
            adapterID: RuntimeAdapterID("sdk"),
            contextPolicy: finalBoundaryTestsMakeContext(),
            input: RuntimeSensitiveInput("not persisted"),
        )
        try await plane.projectPrelaunch(request, as: .policyReady)

        for context in mutatedExecutionContexts(from: request.contextPolicy) {
            let changed = RuntimeLaunchRequest(
                externalAgentSessionReference: request.externalAgentSessionReference,
                runReference: request.runReference,
                adapterID: request.adapterID,
                contextPolicy: context,
                input: request.input,
            )
            await #expect(throws: RuntimeHostError.invalidEvent) {
                try await plane.run(changed)
            }
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-capture_external_agent_context_policy: restart identity includes namespace and excludes sensitive
    /// context.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `restart identity includes namespace and excludes sensitive context`() async throws {
        let stored = finalBoundaryTestsMakeStored(
            host: "host-restart",
            run: RuntimeRunReference("run-restart"),
            providerNamespace: "provider-a",
        )
        let data = try JSONEncoder().encode(finalBoundaryTestsMakeState([stored]))
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(!json.contains("/private/workspace"))
        #expect(!json.contains("sensitive-request"))

        let adapter = finalBoundaryTestsMakeAdapter(providerNamespace: "provider-b")
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: finalBoundaryTestsMakeState([stored])))
        try await plane.register(adapter)
        #expect(try await plane.restore(
            hostReference: "host-restart",
            expectedContext: finalBoundaryTestsMakeContext(),
        ) == .stale)
    }

    /// ATI-006-capture_external_agent_context_policy: approval carries canonical correlation.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `approval carries canonical correlation`() async throws {
        let host: ExternalAgentSessionReference = "host-approval-correlation"
        let run = RuntimeRunReference("run-approval-correlation")
        let adapter = finalBoundaryTestsMakeApprovalAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        let task = Task { try await plane.run(request) }
        try await waitForProjection(.running, host: host, on: plane)

        try await plane.respondToApproval(
            hostReference: host,
            requestID: RuntimeApprovalRequestID("approval-1"),
            operationID: RuntimeOperationID("operation-1"),
        )

        let approval = try #require(await adapter.receivedApprovalRequests().first)
        #expect(approval.externalAgentSessionReference == host)
        #expect(approval.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
        #expect(approval.requestID == RuntimeApprovalRequestID("approval-1"))
        #expect(approval.authorizationGeneration == 1)
        _ = try await task.value
    }

    /// ATI-006-capture_external_agent_context_policy: approval and queued input route through capability-gated
    /// coordinator methods.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `approval and queued input route through capability-gated coordinator methods`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [
                [
                    makeEvent(
                        host: host,
                        run: run,
                        sequence: 1,
                        idempotencyKey: "done",
                        kind: .completed,
                    ),
                ],
            ],
            eventStreamDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)

        try await plane.respondToApproval(
            hostReference: host,
            requestID: RuntimeApprovalRequestID("approval-request-1"),
            operationID: RuntimeOperationID("approve-1"),
        )
        try await plane.enqueueInput(
            hostReference: host,
            operationID: RuntimeOperationID("input-1"),
            input: RuntimeSensitiveInput("not persisted"),
        )
        _ = try await task.value

        let counts = await adapter.counts()
        #expect(counts.approval == 1)
        #expect(counts.input == 1)
    }

    /// ATI-006-capture_external_agent_context_policy: policy ready prelaunch can proceed to provider launch.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `policy ready prelaunch can proceed to provider launch`() async throws {
        let adapter = finalReviewTestsMakeAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = makeLaunch(host: "host-a", run: RuntimeRunReference("run-a"), adapterID: "sdk")

        try await plane.projectPrelaunch(request, as: .policyPending)
        try await plane.projectPrelaunch(request, as: .policyReady)
        let result = try await runPolicyReady(plane, request)

        #expect(result.outcome == .completed)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-capture_external_agent_context_policy: requested working directory requires adapter capability.
    /// working directory를 적용할 수 없는 adapter가 승인된 실행 컨텍스트 밖에서 시작되지 않는지 검증한다.
    /// - 검증 내용: unknown/unsupported workingDirectory capability의 typed launch 거부.
    /// - 사전 조건: launch context에 workingDirectory가 지정되어 있다.
    /// - 기대 결과: provider launch 전에 capability 오류가 발생하고 adapter는 호출되지 않는다.
    @Test(arguments: [RuntimeCapabilityStatus.unknown, .unsupported])
    func `requested working directory requires adapter capability`(status: RuntimeCapabilityStatus) async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: contextCapabilityTestsMakeCapabilities(workingDirectory: status),
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host-working-directory-capability",
            runReference: RuntimeRunReference("run-working-directory-capability"),
            adapterID: RuntimeAdapterID("sdk"),
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-working-directory-capability",
                workingDirectory: "/tmp/workspace",
            ),
            input: RuntimeSensitiveInput("not persisted"),
        )
        try await plane.projectPrelaunch(request, as: .policyReady)

        if status == .unknown {
            await #expect(throws: RuntimeHostError.capabilityUnknown(.workingDirectory)) {
                _ = try await plane.run(request)
            }
        } else {
            await #expect(throws: RuntimeHostError.capabilityUnsupported(.workingDirectory)) {
                _ = try await plane.run(request)
            }
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-capture_external_agent_context_policy: requested allowed roots require adapter capability.
    /// 추가 root를 적용할 수 없는 adapter가 승인된 root 경계를 무시하고 시작되지 않는지 검증한다.
    /// - 검증 내용: unknown/unsupported additionalRoots capability의 typed launch 거부.
    /// - 사전 조건: launch context에 allowedRoots가 하나 이상 지정되어 있다.
    /// - 기대 결과: provider launch 전에 capability 오류가 발생하고 adapter는 호출되지 않는다.
    @Test(arguments: [RuntimeCapabilityStatus.unknown, .unsupported])
    func `requested allowed roots require adapter capability`(status: RuntimeCapabilityStatus) async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: contextCapabilityTestsMakeCapabilities(additionalRoots: status),
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: "host-additional-roots-capability",
            runReference: RuntimeRunReference("run-additional-roots-capability"),
            adapterID: RuntimeAdapterID("sdk"),
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-additional-roots-capability",
                allowedRoots: ["/tmp/workspace"],
            ),
            input: RuntimeSensitiveInput("not persisted"),
        )
        try await plane.projectPrelaunch(request, as: .policyReady)

        if status == .unknown {
            await #expect(throws: RuntimeHostError.capabilityUnknown(.additionalRoots)) {
                _ = try await plane.run(request)
            }
        } else {
            await #expect(throws: RuntimeHostError.capabilityUnsupported(.additionalRoots)) {
                _ = try await plane.run(request)
            }
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-capture_external_agent_context_policy: sensitive input is bounded.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `sensitive input is bounded`() async throws {
        let adapter = storageBoundaryTestsMakeAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let oversized = String(repeating: "x", count: RuntimeBoundaryLimits.sensitiveInputScalars + 1)
        let base = makeLaunch(host: "host-input", run: RuntimeRunReference("run-input"), adapterID: "sdk")
        let launch = RuntimeLaunchRequest(
            externalAgentSessionReference: base.externalAgentSessionReference,
            runReference: base.runReference,
            adapterID: base.adapterID,
            contextPolicy: base.contextPolicy,
            input: RuntimeSensitiveInput(oversized),
        )

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.projectPrelaunch(launch, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-capture_external_agent_context_policy: file CAS compares persisted execution context semantics.
    /// 파일 CAS가 저장된 실행 컨텍스트 전체를 동일성 판단에 사용하는지 검증한다.
    /// - 검증 내용: 실행 완료, 단일 provider launch, completed projection, 실행 컨텍스트 동일성.
    /// - 사전 조건: working directory, allowed roots, request context를 포함한 policy-ready 요청이 저장되어 있다.
    /// - 기대 결과: 동일한 실행 컨텍스트로 run이 완료되고 persisted session이 completed로 수렴한다.
    @Test
    func `file CAS compares persisted execution context semantics`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host = ExternalAgentSessionReference("host-context-cas")
        let run = RuntimeRunReference("run-context-cas")
        let context = RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "context-cas",
            workingDirectory: "/tmp/voyager-context-cas",
            allowedRoots: ["/tmp/voyager-context-cas", "/tmp/voyager-shared"],
            requestContext: "review-context",
        )
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            contextPolicy: context,
            input: RuntimeSensitiveInput("secret"),
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await plane.register(adapter)

        try await plane.projectPrelaunch(request, as: .policyReady)
        let result = try await plane.run(request)

        #expect(result.outcome == .completed)
        #expect(await adapter.counts().launch == 1)
        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(persisted.sessions.first?.projection == .completed)
        #expect(persisted.sessions.first?.storedContext == RuntimeStoredContext(contextPolicy: context))
    }

    // MARK: - ATI-006-coordinate_external_agent_launch

    /// ATI-006-coordinate_external_agent_launch: shared file preserves independent host mutations.
    /// 두 control plane의 서로 다른 host 변경이 공유 파일에서 유실되지 않는지 검증한다.
    /// - 검증 내용: 두 restore 결과, 두 prelaunch 저장, persisted host 집합.
    /// - 사전 조건: 독립 control plane이 같은 file store를 사용하고 서로 다른 host와 run을 준비한다.
    /// - 기대 결과: 두 host mutation이 모두 저장되고 어느 host도 다른 변경을 덮어쓰지 않는다.
    @Test
    func `shared file preserves independent host mutations`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        ))
        try await secondPlane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        ))
        let first = makeLaunch(
            host: ExternalAgentSessionReference("host-a"),
            run: RuntimeRunReference("run-a"),
            adapterID: "sdk",
        )
        let second = makeLaunch(
            host: ExternalAgentSessionReference("host-b"),
            run: RuntimeRunReference("run-b"),
            adapterID: "sdk",
        )

        #expect(try await firstPlane.restore(
            hostReference: first.externalAgentSessionReference,
            expectedContext: first.contextPolicy,
        ) == .stale)
        #expect(try await secondPlane.restore(
            hostReference: second.externalAgentSessionReference,
            expectedContext: second.contextPolicy,
        ) == .stale)
        try await firstPlane.projectPrelaunch(first, as: .policyReady)
        try await secondPlane.projectPrelaunch(second, as: .policyReady)

        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(Set(persisted.sessions.map(\.externalAgentSessionReference)) == [
            first.externalAgentSessionReference,
            second.externalAgentSessionReference,
        ])
    }

    /// ATI-006-coordinate_external_agent_launch: stale same-host mutation is rejected.
    /// 공유 파일의 최신 same-host 상태를 stale control plane이 덮어쓰지 못하는지 검증한다.
    /// - 검증 내용: 두 restore 결과, stale mutation 오류, persisted session 수와 run reference.
    /// - 사전 조건: 두 control plane이 같은 host에 서로 다른 run을 준비하고 첫 mutation이 먼저 저장된다.
    /// - 기대 결과: stale mutation은 persistenceConflict로 거부되고 최초 run만 durable 상태로 남는다.
    @Test
    func `stale same-host mutation is rejected`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let secondPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await firstPlane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        ))
        try await secondPlane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        ))
        let first = makeLaunch(
            host: ExternalAgentSessionReference("host-a"),
            run: RuntimeRunReference("run-a"),
            adapterID: "sdk",
        )
        let stale = makeLaunch(
            host: first.externalAgentSessionReference,
            run: RuntimeRunReference("run-stale"),
            adapterID: "sdk",
        )

        #expect(try await firstPlane.restore(
            hostReference: first.externalAgentSessionReference,
            expectedContext: first.contextPolicy,
        ) == .stale)
        #expect(try await secondPlane.restore(
            hostReference: stale.externalAgentSessionReference,
            expectedContext: stale.contextPolicy,
        ) == .stale)
        try await firstPlane.projectPrelaunch(first, as: .policyReady)
        await #expect(throws: RuntimeHostError.persistenceConflict) {
            try await secondPlane.projectPrelaunch(stale, as: .policyReady)
        }

        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(persisted.sessions.count == 1)
        #expect(persisted.sessions.first?.runReference == first.runReference)
    }

    /// ATI-006-coordinate_external_agent_launch: process and SDK transports satisfy the same host contract.
    /// transport 종류와 무관하게 동일한 host 실행 계약이 적용되는지 검증한다.
    /// - 검증 내용: process JSONL과 SDK async stream 각각의 completed 결과.
    /// - 사전 조건: 각 transport에 맞는 adapter와 동일 형태의 host/run/event 요청이 구성되어 있다.
    /// - 기대 결과: 두 parameterized transport case 모두 동일한 completed outcome을 반환한다.
    @Test(arguments: [
        RuntimeTransportKind.processJSONL,
        RuntimeTransportKind.sdkAsyncStream,
    ])
    func `process and SDK transports satisfy the same host contract`(transport: RuntimeTransportKind) async throws {
        let host = ExternalAgentSessionReference("host-\(transport.rawValue)")
        let run = RuntimeRunReference("run-\(transport.rawValue)")
        let adapter = DeterministicRuntimeAdapter(
            id: transport.rawValue,
            transport: transport,
            eventsByLaunch: [
                [
                    makeEvent(
                        host: host,
                        run: run,
                        sequence: 1,
                        idempotencyKey: "done",
                        kind: .completed,
                    ),
                ],
            ],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: run,
            adapterID: RuntimeAdapterID(transport.rawValue),
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local",
            ),
            input: RuntimeSensitiveInput("secret payload"),
        ))

        #expect(result.outcome == .completed)
    }

    /// ATI-006-coordinate_external_agent_launch: same host launch is rejected without launching twice.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `same host launch is rejected without launching twice`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let firstRun = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "process",
            transport: .processJSONL,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: firstRun,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
            launchDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let first = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: firstRun, adapterID: "process"))
        }
        await adapter.waitForLaunchCount(1)

        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await runPolicyReady(plane, makeLaunch(
                host: host,
                run: RuntimeRunReference("run-b"),
                adapterID: "process",
            ))
        }
        _ = try await first.value
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: same run reference is rejected across different hosts.
    /// provider correlation에 host가 포함되지 않아도 하나의 run이 둘 이상의 host에 예약되지 않는지 검증한다.
    /// - 검증 내용: control plane 전역 run reference uniqueness와 provider 미호출 경계.
    /// - 사전 조건: 첫 host가 shared run을 policy-ready 상태로 예약했다.
    /// - 기대 결과: 다른 host의 같은 run 예약은 duplicateRunReference로 거부되고 첫 예약만 유지된다.
    @Test
    func `same run reference is rejected across different hosts`() async throws {
        let sharedRun = RuntimeRunReference("run-shared")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let first = makeLaunch(host: "host-a", run: sharedRun, adapterID: "sdk")
        let duplicate = makeLaunch(host: "host-b", run: sharedRun, adapterID: "sdk")

        try await plane.projectPrelaunch(first, as: .policyReady)

        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            try await plane.projectPrelaunch(duplicate, as: .policyReady)
        }
        #expect(await plane.projection(for: first.externalAgentSessionReference) == .policyReady)
        #expect(await plane.projection(for: duplicate.externalAgentSessionReference) == nil)
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-coordinate_external_agent_launch: duplicate adapter registration never replaces the first adapter.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `duplicate adapter registration never replaces the first adapter`() async throws {
        let first = DeterministicRuntimeAdapter(id: "same", transport: .processJSONL, eventsByLaunch: [[]])
        let second = DeterministicRuntimeAdapter(id: "same", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(first)

        await #expect(throws: RuntimeHostError.duplicateAdapterRegistration) {
            try await plane.register(second)
        }
        #expect(await plane.adapterDescriptor(for: RuntimeAdapterID("same"))?.transport == .processJSONL)
    }

    /// ATI-006-coordinate_external_agent_launch: ambiguous launch failure cannot retry the same run reference.
    /// provider 호출 뒤 발생한 오류를 미시작 증거 없이 재시도하지 않는지 검증한다.
    /// - 검증 내용: launch 오류의 원본 반환, interrupted projection, provider 재호출 차단.
    /// - 사전 조건: adapter launch가 receipt 없이 오류를 반환한다.
    /// - 기대 결과: 첫 호출은 adapterUnavailable이고 같은 run은 duplicate로 거부된다.
    @Test
    func `ambiguous launch failure cannot retry the same run reference`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchFailures: 1,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = makeLaunch(host: "host-a", run: RuntimeRunReference("run-a"), adapterID: "sdk")

        await #expect(throws: RuntimeHostError.adapterUnavailable) { _ = try await runPolicyReady(plane, request) }
        await #expect(throws: RuntimeHostError.duplicateRunReference) { _ = try await runPolicyReady(plane, request) }
        #expect(await plane.projection(for: request.externalAgentSessionReference) == .interrupted)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: cancellation wins during launch failure cleanup.
    /// adapter 실패 정리가 persistence에서 대기하는 동안 caller 취소가 원래 오류보다 우선하는지 검증한다.
    /// - 검증 내용: CancellationError 전파와 exact launch lease 정리.
    /// - 사전 조건: adapter launch 실패 뒤 interrupted snapshot 저장이 gate에서 대기한다.
    /// - 기대 결과: caller는 CancellationError를 받고 host는 active launch lease를 남기지 않는다.
    @Test
    func `cancellation wins during launch failure cleanup`() async throws {
        let host: ExternalAgentSessionReference = "host-launch-failure-cleanup-cancelled"
        let run = RuntimeRunReference("run-launch-failure-cleanup-cancelled")
        let cleanupSaveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [3: cleanupSaveGate])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchFailures: 1,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await store.waitForSaveCount(3)

        task.cancel()
        await cleanupSaveGate.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await plane.sessions[host]?.lease.isActive == false)
    }

    /// ATI-006-coordinate_external_agent_launch: cancelling launch wait preserves the attempted reservation.
    /// receipt 전 caller task 취소를 adapter 실패나 명시적 interruption으로 저장하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, launching projection 보존, provider 재호출 차단.
    /// - 사전 조건: adapter launch가 receipt 반환 전 cancellation-aware delay에서 대기한다.
    /// - 기대 결과: attempted reservation은 fail-closed로 남고 같은 run은 duplicate로 거부된다.
    @Test
    func `cancelled launch wait preserves the attempted reservation`() async throws {
        let host: ExternalAgentSessionReference = "host-launch-cancelled"
        let run = RuntimeRunReference("run-launch-cancelled")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchDelay: .seconds(2),
        )
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, request) }
        await adapter.waitForLaunchCount(1)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.projection(for: host) == .launching)
        #expect(await store.currentState()?.sessions.first?.projection == .launching)
        #expect(await adapter.counts().launch == 1)

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            try await recoveredPlane.projectPrelaunch(request, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: restarted attempted launch remains fail-closed.
    /// provider 시작 사실이 저장된 launching snapshot을 terminal 증거 없이 회수하지 않는지 검증한다.
    /// - 검증 내용: same-run duplicate 거부, launching projection 보존, replacement 차단, provider 미호출.
    /// - 사전 조건: provider handle 없이 launch 시도 사실만 저장된 snapshot을 새 control plane이 hydrate한다.
    /// - 기대 결과: snapshot은 interrupted로 합성되지 않고 host는 terminal 증거 전까지 재사용되지 않는다.
    @Test
    func `restarted attempted launch remains fail closed`() async throws {
        let host: ExternalAgentSessionReference = "host-restarted-attempted-launch"
        let run = RuntimeRunReference("run-restarted-attempted-launch")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
            projection: .launching,
            providerLaunchAttempted: true,
            providerNamespace: "sdk",
            providerBranch: .unknown,
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await plane.run(request)
        }

        #expect(await plane.projection(for: host) == .launching)
        let replacement = makeLaunch(
            host: host,
            run: RuntimeRunReference("run-restarted-attempted-replacement"),
            adapterID: "sdk",
        )
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await plane.projectPrelaunch(replacement, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-coordinate_external_agent_launch: terminal evidence releases a cancelled launch reservation.
    /// caller가 사라진 launch의 terminal 증거가 남은 reservation을 회수해 host 재사용을 허용하는지 검증한다.
    /// - 검증 내용: CancellationError 전파, same-run terminal 수용, replacement provider 실행.
    /// - 사전 조건: adapter launch가 cancellation-aware delay에서 대기하다 caller task가 취소된다.
    /// - 기대 결과: terminal 저장 뒤 replacement가 activeRunExists 없이 완료되고 provider launch는 총 두 번이다.
    @Test
    func `terminal evidence releases a cancelled launch reservation`() async throws {
        let host: ExternalAgentSessionReference = "host-cancelled-launch-terminal"
        let cancelledRun = RuntimeRunReference("run-cancelled-launch-terminal")
        let replacementRun = RuntimeRunReference("run-cancelled-launch-replacement")
        let replacementCompleted = makeEvent(
            host: host,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "cancelled-launch-replacement-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[], [replacementCompleted]],
            launchDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let cancelledRequest = makeLaunch(host: host, run: cancelledRun, adapterID: "sdk")
        let cancelledTask = Task { try await runPolicyReady(plane, cancelledRequest) }
        await adapter.waitForLaunchCount(1)

        cancelledTask.cancel()
        await #expect(throws: CancellationError.self) { try await cancelledTask.value }
        #expect(try await plane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: host, run: cancelledRun, sequence: 1),
        )?.outcome == .completed)

        let replacement = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")
        try await plane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await plane.run(replacement).outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    /// ATI-006-coordinate_external_agent_launch: cancelled persistence waiter never launches a provider.
    /// provider 호출 전 persistence lock 대기에서 취소된 작업이 mutation과 외부 실행을 진행하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, cancelled host 저장 차단, provider launch 미호출.
    /// - 사전 조건: 다른 host의 prelaunch 저장이 persistence lock을 보유하고 run 작업이 waiter로 대기한다.
    /// - 기대 결과: lock 해제 뒤 취소된 waiter는 mutation 전에 중단되고 provider side effect가 발생하지 않는다.
    @Test
    func `cancelled persistence waiter does not launch a provider`() async throws {
        let saveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [1: saveGate])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let lockHolder = makeLaunch(
            host: "host-persistence-lock-holder",
            run: RuntimeRunReference("run-persistence-lock-holder"),
            adapterID: "sdk",
        )
        let cancelled = makeLaunch(
            host: "host-persistence-waiter-cancelled",
            run: RuntimeRunReference("run-persistence-waiter-cancelled"),
            adapterID: "sdk",
        )
        let lockHolderTask = Task {
            try await plane.projectPrelaunch(lockHolder, as: .policyPending)
        }
        await store.waitForSaveCount(1)

        let cancelledTask = Task { try await runPolicyReady(plane, cancelled) }
        try await reviewerBlockerTestsWaitForPersistenceWaiters(1, on: plane)
        cancelledTask.cancel()
        await saveGate.open()

        try await lockHolderTask.value
        await #expect(throws: CancellationError.self) { try await cancelledTask.value }
        #expect(await adapter.counts().launch == 0)
        #expect(await plane.projection(for: cancelled.externalAgentSessionReference) == nil)
        #expect(
            await store.currentState()?.sessions.contains {
                $0.externalAgentSessionReference == cancelled.externalAgentSessionReference
            } == false,
        )
    }

    /// ATI-006-coordinate_external_agent_launch: store cancellation remains caller cancellation.
    /// 실제 store save 내부에서 발생한 취소가 persistenceFailure로 정규화되지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파와 prelaunch snapshot 미저장.
    /// - 사전 조건: 첫 prelaunch save가 cancellation-aware delay에서 대기한다.
    /// - 기대 결과: 취소된 호출은 원래 오류로 종료되고 durable session은 생성되지 않는다.
    @Test
    func `store cancellation remains caller cancellation`() async throws {
        let store = InMemoryRuntimeStateStore(saveDelays: [1: .seconds(2)])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        ))
        let request = makeLaunch(
            host: "host-store-save-cancellation",
            run: RuntimeRunReference("run-store-save-cancellation"),
            adapterID: "sdk",
        )
        let task = Task { try await plane.projectPrelaunch(request, as: .policyReady) }
        await store.waitForSaveCount(1)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.projection(for: request.externalAgentSessionReference) == nil)
        #expect(await store.currentState() == nil)
    }

    /// ATI-006-coordinate_external_agent_launch: ambiguous launch cleanup failure remains fail-closed.
    /// provider 호출 오류 뒤 cleanup 저장도 실패하면 durable reservation을 재실행하지 않는지 검증한다.
    /// - 검증 내용: 최초 adapter 오류 보존, restart 후 같은 run prelaunch 차단, launch 횟수.
    /// - 사전 조건: launch가 오류를 반환하고 interrupted cleanup 저장이 실패한다.
    /// - 기대 결과: persisted attempted reservation은 duplicate로 거부되고 provider는 한 번만 호출된다.
    @Test
    func `ambiguous launch cleanup failure remains fail-closed`() async throws {
        let host: ExternalAgentSessionReference = "host-cleanup-recovery"
        let run = RuntimeRunReference("run-cleanup-recovery")
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchFailures: 1,
        )
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let firstPlane = RuntimeControlPlane(store: store)
        try await firstPlane.register(adapter)
        try await firstPlane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await firstPlane.run(request)
        }

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            try await recoveredPlane.projectPrelaunch(request, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: malformed launch receipt remains fail-closed when cleanup save fails.
    /// provider가 시작된 뒤 malformed receipt와 cleanup 저장 실패가 겹쳐도 중복 launch를 막는지 검증한다.
    /// - 검증 내용: 최초 malformed 오류 보존, restart 후 동일 run의 prelaunch 차단, provider launch 횟수.
    /// - 사전 조건: provider handle이 경계를 초과하고 interrupted cleanup snapshot 저장이 실패한다.
    /// - 기대 결과: 호출자는 malformed 오류를 받고 durable launching snapshot은 다시 실행 가능 상태로 해석되지 않는다.
    @Test
    func `malformed launch receipt remains fail-closed when cleanup save fails`() async throws {
        let host: ExternalAgentSessionReference = "host-malformed-receipt"
        let run = RuntimeRunReference("run-malformed-receipt")
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            IDs: DeterministicRuntimeIDs { _ in
                ProviderInternalSessionReference(String(
                    repeating: "x",
                    count: RuntimeBoundaryLimits.opaqueProviderHandleScalars + 1,
                ))
            },
        )
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let firstPlane = RuntimeControlPlane(store: store)
        try await firstPlane.register(adapter)
        try await firstPlane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await firstPlane.run(request)
        }

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            try await recoveredPlane.projectPrelaunch(request, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: recoverable prelaunch preserves accumulated event evidence.
    /// 같은 run의 pre-provider projection을 다시 계산할 때 이미 저장된 event cursor를 보존하는지 검증한다.
    /// - 검증 내용: provider와 host sequence, accepted/processed count, idempotency key, event evidence.
    /// - 사전 조건: provider handle 없는 launching snapshot에 양쪽 source의 처리 증거가 저장되어 있다.
    /// - 기대 결과: policy-ready 전환은 projection만 바꾸고 누적된 replay 방지 증거를 유지한다.
    @Test
    func `recoverable prelaunch preserves accumulated event evidence`() async throws {
        let host: ExternalAgentSessionReference = "host-prelaunch-evidence"
        let run = RuntimeRunReference("run-prelaunch-evidence")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: request.contextPolicy),
            projection: .launching,
            providerLaunchAttempted: false,
            lastSequence: 7,
            acceptedEventCount: 8,
            processedEventCount: 9,
            acceptedIdempotencyKeys: [RuntimeIdempotencyKey("provider-event")],
            hostLastSequence: 4,
            hostAcceptedEventCount: 4,
            hostProcessedEventCount: 5,
            providerNamespace: "sdk",
            providerBranch: .unknown,
            eventEvidence: [.sequenceGap(expected: 6, received: 7)],
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        try await plane.projectPrelaunch(request, as: .policyReady)

        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.lastSequence == 7)
        #expect(persisted.acceptedEventCount == 8)
        #expect(persisted.processedEventCount == 9)
        #expect(persisted.acceptedIdempotencyKeys == [RuntimeIdempotencyKey("provider-event")])
        #expect(persisted.eventEvidence == [RuntimeEventEvidence.sequenceGap(expected: 6, received: 7)])
        #expect(persisted.hostLastSequence == 4)
        #expect(persisted.hostAcceptedEventCount == 4)
        #expect(persisted.hostProcessedEventCount == 5)
    }

    /// ATI-006-coordinate_external_agent_launch: bind persistence failure cannot relaunch a started provider run.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: provider receipt 이후 bind 저장 실패를 pre-provider launch 실패와 구분하고 provider handle을 보존한다.
    /// - 사전 조건: provider launch는 성공하고 bind snapshot 저장만 실패한다.
    /// - 기대 결과: run은 provider handle을 포함한 interrupted로 보존되고 동일 run 재시도가 provider를 다시 시작하지 않는다.
    @Test
    func `bind persistence failure cannot relaunch a started provider run`() async throws {
        let host: ExternalAgentSessionReference = "host-bind-failure"
        let run = RuntimeRunReference("run-bind-failure")
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let firstPlane = RuntimeControlPlane(store: store)
        try await firstPlane.register(adapter)
        try await firstPlane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await firstPlane.run(request)
        }
        let interrupted = try #require(await store.currentState()?.sessions.first)
        #expect(interrupted.projection == .interrupted)
        #expect(interrupted.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await recoveredPlane.run(request)
        }
        #expect(await recoveredPlane.projection(for: host) == .interrupted)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: interrupted cleanup retry cannot reopen a started provider run.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: bind 저장과 첫 interrupted 정리 저장이 연속 실패해도 provider 시작 사실을 유지한다.
    /// - 사전 조건: provider receipt 이후 세 번째와 네 번째 snapshot 저장이 실패한다.
    /// - 기대 결과: 후속 정리는 interrupted를 저장하고 동일 run 재시도가 provider를 다시 시작하지 않는다.
    @Test
    func `interrupted cleanup retry cannot reopen a started provider run`() async throws {
        let host: ExternalAgentSessionReference = "host-bind-double-failure"
        let run = RuntimeRunReference("run-bind-double-failure")
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3, 4])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let firstPlane = RuntimeControlPlane(store: store)
        try await firstPlane.register(adapter)
        try await firstPlane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await firstPlane.run(request)
        }

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await recoveredPlane.run(request)
        }
        let recoveredProjection = await recoveredPlane.projection(for: host)
        #expect(recoveredProjection == .launching
            || recoveredProjection == .running
            || recoveredProjection == .interrupted)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: completed run retry never launches the provider twice.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `completed run retry never launches the provider twice`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "process",
            transport: .processJSONL,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "process")
        _ = try await runPolicyReady(plane, request)

        await #expect(throws: RuntimeHostError.duplicateRunReference) {
            _ = try await runPolicyReady(plane, request)
        }
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-coordinate_external_agent_launch: adapter launch failure is normalized to bounded host error.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `adapter launch failure is normalized to bounded host error`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            failsLaunch: true,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await runPolicyReady(plane, makeLaunch(
                host: ExternalAgentSessionReference("host-a"),
                run: RuntimeRunReference("run-a"),
                adapterID: "sdk",
            ))
        }
    }

    /// ATI-006-coordinate_external_agent_launch: prelaunch blocked and cancelled never launch provider.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `prelaunch blocked and cancelled never launch provider`() async throws {
        let adapter = finalReviewTestsMakeAdapter()
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        try await plane.projectPrelaunch(
            makeLaunch(host: "host-a", run: RuntimeRunReference("run-a"), adapterID: "sdk"),
            as: .launchBlocked,
        )
        try await plane.projectPrelaunch(
            makeLaunch(host: "host-b", run: RuntimeRunReference("run-b"), adapterID: "sdk"),
            as: .launchCancelled,
        )

        #expect(await plane.projection(for: "host-a") == .launchBlocked)
        #expect(await plane.projection(for: "host-b") == .launchCancelled)
        #expect(await adapter.counts().launch == 0)
    }

    // MARK: - ATI-006-coordinate_external_agent_run_continuity

    /// ATI-006-coordinate_external_agent_run_continuity: shared file admits only one resume owner.
    /// 공유 파일에서 동일 provider run의 resume owner가 하나만 선택되는지 검증한다.
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
        let context = storageBoundaryTestsMakeContext()
        let result = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://shared-restore.json"],
        )
        let capabilities = storageBoundaryTestsMakeCapabilities()
        let stored = storageBoundaryTestsMakeStored(host: host, run: run)
        let seed = RuntimeFileStateStore(fileURL: fileURL)
        try await seed.seed(storageBoundaryTestsMakeState([stored]))
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
        if secondRestore == .restored {
            let duplicateResume = Task { try await secondPlane.resumeRestoredRun(hostReference: host) }
            await adapter.waitForTerminalResultCount(2)
            await terminalGate.open()
            _ = try? await duplicateResume.value
        } else {
            await #expect(throws: RuntimeHostError.invalidEvent) {
                try await secondPlane.resumeRestoredRun(hostReference: host)
            }
            await terminalGate.open()
        }

        #expect(try await firstResume.value == result)
        #expect(await adapter.counts().stream == 0)
        let persisted = try #require(try await RuntimeFileStateStore(fileURL: fileURL).load())
        #expect(persisted.sessions.first?.projection == .completed)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration rejects duplicate run references atomically.
    /// hydration이 서로 다른 host의 중복 run reference를 부분 설치 없이 거부하는지 검증한다.
    /// - 검증 내용: duplicate-run snapshot validation의 typed invalidSnapshot 오류.
    /// - 사전 조건: 서로 다른 두 host가 동일한 run reference를 가진 persisted state가 제공된다.
    /// - 기대 결과: 전체 snapshot 검증이 실패하고 어떤 중복 session도 runtime registry에 설치되지 않는다.
    @Test
    func `hydration rejects duplicate run references atomically`() async throws {
        let run = RuntimeRunReference("run-shared")
        let state = storageBoundaryTestsMakeState([
            storageBoundaryTestsMakeStored(host: "host-a", run: run),
            storageBoundaryTestsMakeStored(host: "host-b", run: run),
        ])
        let store = InMemoryRuntimeStateStore(state: state)
        let plane = RuntimeControlPlane(store: store)

        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await plane.hydrateIfNeeded()
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
        #expect(await store.loadCount == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration preserves caller cancellation.
    /// 공유 load 결과가 성공해도 취소된 waiter의 취소 의미를 보존하는지 검증한다.
    /// - 검증 내용: CancellationError 원형 전파와 hydration 상태 미설치.
    /// - 사전 조건: 단일 waiter가 gated store load를 기다린 뒤 caller에서 취소된다.
    /// - 기대 결과: waiter는 CancellationError를 받고 session registry와 hydrated 상태는 그대로다.
    @Test
    func `hydration preserves caller cancellation`() async throws {
        let gate = RuntimeTestGate()
        let stored = storageBoundaryTestsMakeStored(host: "host-cancelled", run: RuntimeRunReference("run-cancelled"))
        let store = InMemoryRuntimeStateStore(
            state: storageBoundaryTestsMakeState([stored]),
            loadGates: [1: gate],
        )
        let plane = RuntimeControlPlane(store: store)
        let task = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)

        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
        #expect(await store.loadCount == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration cancellation does not cancel a shared load.
    /// 한 waiter의 취소가 actor-owned shared load와 다른 waiter의 완전 설치를 방해하지 않는지 검증한다.
    /// - 검증 내용: 두 caller의 CancellationError/성공 결과, 단일 load와 단일 install.
    /// - 사전 조건: 두 waiter가 동일한 gated load를 공유하고 caller A만 먼저 취소된다.
    /// - 기대 결과: caller A는 취소되고 caller B는 전체 registry를 한 번 설치하며 task가 정리된다.
    @Test
    func `hydration cancellation does not cancel a shared load`() async throws {
        let gate = RuntimeTestGate()
        let sessions = [
            storageBoundaryTestsMakeStored(host: "host-shared-a", run: RuntimeRunReference("run-shared-a")),
            storageBoundaryTestsMakeStored(host: "host-shared-b", run: RuntimeRunReference("run-shared-b")),
        ]
        let store = InMemoryRuntimeStateStore(
            state: storageBoundaryTestsMakeState(sessions),
            loadGates: [1: gate],
        )
        let plane = RuntimeControlPlane(store: store)
        let first = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)
        let second = Task { try await plane.hydrateIfNeeded() }
        await plane.waitForHydrationWaiters(2)
        #expect(await plane.hydrationWaiterCount == 2)

        first.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) { try await first.value }
        try await second.value
        #expect(await plane.sessions.count == 2)
        #expect(await plane.hydrated)
        #expect(await plane.hydrationInstallCount == 1)
        #expect(await plane.hydrationTask == nil)
        #expect(await store.loadCount == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration maps unsupported schema without partial install.
    /// store의 unsupported schema 오류가 partial hydration 없이 그대로 control-plane 오류로 변환되는지 검증한다.
    /// - 검증 내용: schema 오류, session registry, hydrated 플래그, shared task cleanup.
    /// - 사전 조건: 현재 schema보다 큰 schema와 설치 대상 session이 함께 저장되어 있다.
    /// - 기대 결과: unsupportedSchemaVersion이 보존되고 아무 session도 설치되지 않는다.
    @Test
    func `hydration maps unsupported schema without partial install`() async throws {
        let version = RuntimeStoredState.currentSchemaVersion + 1
        let state = RuntimeStoredState(
            schemaVersion: version,
            sessions: [storageBoundaryTestsMakeStored(host: "host-future", run: RuntimeRunReference("run-future"))],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: state))

        await #expect(throws: RuntimeHostError.unsupportedSchemaVersion(version)) {
            try await plane.hydrateIfNeeded()
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration maps invalid snapshot without partial install.
    /// store structural validation 오류가 lifecycle registry 설치 전에 종료되는지 검증한다.
    /// - 검증 내용: invalidPersistedState mapping과 unchanged runtime state.
    /// - 사전 조건: persisted counter invariant를 위반하는 snapshot이 제공된다.
    /// - 기대 결과: invalidPersistedState가 발생하고 registry는 비어 있으며 task는 정리된다.
    @Test
    func `hydration maps invalid snapshot without partial install`() async throws {
        let invalid = storageBoundaryTestsMakeStored(
            host: "host-invalid",
            run: RuntimeRunReference("run-invalid"),
            acceptedEventCount: -1,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(
            state: storageBoundaryTestsMakeState([invalid]),
        ))

        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await plane.hydrateIfNeeded()
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration maps unavailable store without partial install.
    /// unavailable store 오류가 persistenceFailure로 변환되면서 runtime state를 보존하는지 검증한다.
    /// - 검증 내용: unavailable mapping, unchanged registry, cleanup.
    /// - 사전 조건: 첫 shared load가 unavailable store 오류를 반환한다.
    /// - 기대 결과: persistenceFailure가 발생하고 partial install 없이 task가 nil이 된다.
    @Test
    func `hydration maps unavailable store without partial install`() async throws {
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(failingLoadNumbers: [1]))

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.hydrateIfNeeded()
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration delivers an observed failure across generation
    /// cleanup.
    /// 이전 generation의 failure를 본 waiter가 새 generation을 시작해도 다른 waiter에게 동일 오류가 전달되는지 검증한다.
    /// - 검증 내용: 두 waiter의 persistenceFailure, 두 번의 load, 새 generation의 완전 설치와 cleanup.
    /// - 사전 조건: 두 waiter가 첫 unavailable load를 공유하고 첫 waiter가 cleanup한 뒤 새 generation이 시작된다.
    /// - 기대 결과: 두 번째 waiter는 성공으로 끝나지 않고 같은 persistenceFailure를 받으며 새 generation만 설치된다.
    @Test
    func `hydration delivers an observed failure across generation cleanup`() async throws {
        let firstLoadGate = RuntimeTestGate()
        let stored = storageBoundaryTestsMakeStored(
            host: "host-next-generation",
            run: RuntimeRunReference("run-next-generation"),
        )
        let store = InMemoryRuntimeStateStore(
            state: storageBoundaryTestsMakeState([stored]),
            failingLoadNumbers: [1],
            loadGates: [1: firstLoadGate],
        )
        let plane = RuntimeControlPlane(store: store)
        let first = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)
        let second = Task(priority: .background) { try await plane.hydrateIfNeeded() }
        await plane.waitForHydrationWaiters(2)
        #expect(await plane.hydrationWaiterCount == 2)
        await plane.pauseBackgroundHydrationDelivery()
        await firstLoadGate.open()
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await first.value }
        await plane.waitForHydrationDeliveryPause()
        #expect(await plane.hydrationDeliveryIsPaused)

        let nextGeneration = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(2)
        try await nextGeneration.value
        await plane.resumeHydrationDelivery()
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await second.value }

        #expect(await store.loadCount == 2)
        #expect(await plane.sessions.count == 1)
        #expect(await plane.hydrated)
        #expect(await plane.hydrationTask == nil)
        #expect(await plane.hydrationInstallCount == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration rejects projection without provider session
    /// reference atomically.
    /// provider session reference가 필요한 projection의 lifecycle invariant를 hydration에서 검증하는지 확인한다.
    /// - 검증 내용: running projection의 provider reference 누락, invalidPersistedState, partial install 방지.
    /// - 사전 조건: running snapshot이 provider session reference 없이 저장되어 있다.
    /// - 기대 결과: lifecycle validation 오류가 발생하고 registry와 hydrated state가 변경되지 않는다.
    @Test
    func `hydration rejects provider-inconsistent projection atomically`() async throws {
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: "host-provider-mismatch",
            providerInternalSessionReference: nil,
            runReference: RuntimeRunReference("run-provider-mismatch"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: finalBoundaryTestsMakeContext()),
            projection: .running,
            providerNamespace: "provider-a",
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(
            state: finalBoundaryTestsMakeState([stored]),
        ))
        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await plane.hydrateIfNeeded()
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration installs a valid multi-host snapshot atomically.
    /// lifecycle validation을 통과한 전체 snapshot이 한 번의 완전 설치로 registry에 반영되는지 검증한다.
    /// - 검증 내용: 두 host/session 설치, hydrated 전환, shared load/install 횟수.
    /// - 사전 조건: 구조적으로 유효한 서로 다른 두 host와 run reference가 저장되어 있다.
    /// - 기대 결과: 두 session이 모두 설치되고 partial registry 없이 정확히 한 번 완료된다.
    @Test
    func `hydration installs a valid multi-host snapshot atomically`() async throws {
        let sessions = [
            storageBoundaryTestsMakeStored(host: "host-valid-a", run: RuntimeRunReference("run-valid-a")),
            storageBoundaryTestsMakeStored(host: "host-valid-b", run: RuntimeRunReference("run-valid-b")),
        ]
        let store = InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState(sessions))
        let plane = RuntimeControlPlane(store: store)

        try await plane.hydrateIfNeeded()

        #expect(await plane.sessions.count == 2)
        #expect(await plane.hydrated)
        #expect(await plane.hydrationInstallCount == 1)
        #expect(await plane.hydrationTask == nil)
        #expect(await store.loadCount == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: stale hydration completion cannot install or clear current
    /// generation.
    /// 이전 generation의 완료가 현재 generation의 shared task와 registry를 침범하지 않는지 검증한다.
    /// - 검증 내용: stale completion no-op, current task 보존, 이후 valid install.
    /// - 사전 조건: 첫 load waiter가 대기 중인 동안 actor generation과 current task가 교체된다.
    /// - 기대 결과: 이전 결과는 설치하지 않고 current task를 유지하며 현재 generation만 설치한다.
    @Test
    func `stale hydration completion cannot install or clear current generation`() async throws {
        let staleGate = RuntimeTestGate()
        let staleState = storageBoundaryTestsMakeState([
            storageBoundaryTestsMakeStored(host: "host-stale", run: RuntimeRunReference("run-stale")),
        ])
        let store = InMemoryRuntimeStateStore(state: staleState, loadGates: [1: staleGate])
        let plane = RuntimeControlPlane(store: store)
        let staleWaiter = Task { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)

        let currentState = storageBoundaryTestsMakeState([
            storageBoundaryTestsMakeStored(host: "host-current", run: RuntimeRunReference("run-current")),
        ])
        let currentTask = Task<RuntimeStoredState?, Error> { currentState }
        await plane.testSupersedeHydration(with: currentTask)
        await staleGate.open()
        try await staleWaiter.value

        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask != nil)

        try await plane.hydrateIfNeeded()
        #expect(await Set(plane.sessions.keys) == ["host-current"])
        #expect(await plane.hydrationInstallCount == 1)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: stale lifecycle failure cannot clear current generation.
    /// 이전 generation의 invalidPersistedState가 새 generation의 shared task를 지우지 않는지 검증한다.
    /// - 검증 내용: 두 waiter의 정확한 오류 전달, generation 2 task 보존, 무변경 stale state와 단일 설치.
    /// - 사전 조건: generation 1은 lifecycle-invalid snapshot이고 waiter B의 validation failure delivery가 지연된다.
    /// - 기대 결과: waiter A/B는 invalidPersistedState를 받고 generation 2만 한 번 설치된다.
    @Test
    func `stale lifecycle failure cannot clear current generation`() async throws {
        let fixture = await makeStaleLifecycleHydrationFixture()
        await fixture.store.waitForLoadCount(1)
        await fixture.plane.waitForHydrationWaiters(2)
        #expect(await fixture.plane.hydrationWaiterCount == 2)
        await fixture.plane.pauseBackgroundHydrationDelivery()

        await fixture.firstLoadGate.open()
        await #expect(throws: RuntimeHostError.invalidPersistedState) { try await fixture.first.value }
        await fixture.plane.waitForHydrationDeliveryPause()
        #expect(await fixture.plane.hydrationDeliveryIsPaused)

        await fixture.store.replaceState(finalBoundaryTestsMakeState([fixture.validStored]))
        let nextGeneration = Task { try await fixture.plane.hydrateIfNeeded() }
        await fixture.store.waitForLoadCount(2)
        #expect(await fixture.plane.hydrationGeneration == 2)
        #expect(await fixture.plane.sessions.isEmpty)
        #expect(await fixture.plane.hydrated == false)
        #expect(await fixture.plane.hydrationInstallCount == 0)
        #expect(await fixture.plane.hydrationTask != nil)

        await fixture.plane.resumeHydrationDelivery()
        await #expect(throws: RuntimeHostError.invalidPersistedState) { try await fixture.second.value }
        #expect(await fixture.plane.hydrationGeneration == 2)
        #expect(await fixture.plane.sessions.isEmpty)
        #expect(await fixture.plane.hydrated == false)
        #expect(await fixture.plane.hydrationInstallCount == 0)
        #expect(await fixture.plane.hydrationTask != nil)

        await fixture.secondLoadGate.open()
        try await nextGeneration.value
        #expect(await fixture.store.loadCount == 2)
        #expect(await fixture.plane.hydrationGeneration == 2)
        #expect(await Set(fixture.plane.sessions.keys) == ["host-valid-generation"])
        #expect(await fixture.plane.hydrated)
        #expect(await fixture.plane.hydrationInstallCount == 1)
        #expect(await fixture.plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: current generation cleanup is independent of stale waiters.
    /// stale generation waiter가 남아 있어도 현재 generation의 취소 cleanup과 다음 hydration 재시작이 독립적인지 검증한다.
    /// - 검증 내용: 세대별 waiter ownership, current task cleanup, completed task 재사용 방지.
    /// - 사전 조건: generation 1 background waiter가 delivery pause에 머문 동안 generation 2의 sole waiter가 취소된다.
    /// - 기대 결과: generation 2 task가 즉시 정리되고 generation 3은 새 load로 정상 hydration된다.
    @Test
    func `current hydration cleanup is independent of stale generation waiters`() async throws {
        let fixture = makeHydrationGenerationOwnershipFixture()
        let store = fixture.store
        let plane = fixture.plane
        await store.waitForLoadCount(1)
        let stale = fixture.stale
        await plane.waitForHydrationWaiters(2)
        await plane.pauseBackgroundHydrationDelivery()

        await fixture.firstLoadGate.open()
        await #expect(throws: RuntimeHostError.invalidPersistedState) { try await fixture.first.value }
        await plane.waitForHydrationDeliveryPause()

        await store.replaceState(finalBoundaryTestsMakeState([fixture.validStored]))
        let current = Task(priority: .high) { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(2)
        current.cancel()
        await fixture.secondLoadGate.open()

        await #expect(throws: CancellationError.self) { try await current.value }
        #expect(await plane.hydrationTask == nil)
        #expect(await plane.hydrationGeneration == 2)

        await plane.resumeHydrationDelivery()
        await #expect(throws: RuntimeHostError.invalidPersistedState) { try await stale.value }

        try await plane.hydrateIfNeeded()
        #expect(await store.loadCount == 3)
        #expect(await plane.hydrationGeneration == 3)
        #expect(await plane.sessions.count == 1)
        #expect(await plane.hydrationInstallCount == 1)
        #expect(await plane.hydrationTask == nil)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: failed save cannot erase concurrent restored lease.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `failed save cannot erase concurrent restored lease`() async throws {
        let context = reviewerBlockerTestsMakeCanonicalContext()
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: "host-restore",
            run: RuntimeRunReference("run-restore"),
            context: context,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
            failingSaveNumbers: [1],
            saveDelays: [1: .milliseconds(100)],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            restartDelay: .milliseconds(20),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let failing = Task {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: "host-failing",
                    run: RuntimeRunReference("run-failing"),
                    adapterID: "sdk",
                ),
                as: .launchBlocked,
            )
        }
        try await Task.sleep(for: .milliseconds(10))

        #expect(try await plane.restore(hostReference: "host-restore", expectedContext: context) == .restored)
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await failing.value }
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await plane.restore(hostReference: "host-restore", expectedContext: context)
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: prelaunch cannot replace hydrated running session.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `prelaunch cannot replace hydrated running session`() async throws {
        let context = reviewerBlockerTestsMakeCanonicalContext()
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: "host-running",
            run: RuntimeRunReference("run-running"),
            context: context,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        ))

        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: "host-running",
                    run: RuntimeRunReference("run-running"),
                    adapterID: "sdk",
                ),
                as: .policyReady,
            )
        }
        #expect(await plane.projection(for: "host-running") == .running)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: stale file plane admits replacement after durable terminal.
    /// 다른 control plane이 저장한 기존 run의 terminal을 stale plane이 replacement 차단 전에 동기화하는지 검증한다.
    /// - 검증 내용: exact host/run terminal 수렴, replacement prelaunch와 provider launch 횟수.
    /// - 사전 조건: 공유 file store에서 stale plane은 running을 hydrate하고 다른 plane은 같은 run을 completed로 저장한다.
    /// - 기대 결과: stale plane은 durable terminal을 반영한 뒤 같은 host의 replacement run을 한 번 실행한다.
    @Test
    func `stale file plane admits replacement after durable terminal`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host: ExternalAgentSessionReference = "host-stale-prelaunch"
        let originalRun = RuntimeRunReference("run-stale-prelaunch-original")
        let replacementRun = RuntimeRunReference("run-stale-prelaunch-replacement")
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: host,
            run: originalRun,
            context: reviewerBlockerTestsMakeCanonicalContext(),
        )
        try await RuntimeFileStateStore(fileURL: fileURL).seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let replacementAdapter = DeterministicRuntimeAdapter(
            id: "replacement",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: replacementRun,
                sequence: 1,
                idempotencyKey: "stale-prelaunch-replacement-completed",
                kind: .completed,
            )]],
        )
        let stalePlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await stalePlane.register(replacementAdapter)
        try await stalePlane.hydrateIfNeeded()
        #expect(await stalePlane.projection(for: host) == .running)

        let hostPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        #expect(try await hostPlane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: originalRun,
            sequence: 1,
        ))?.outcome == .completed)
        #expect(try await RuntimeFileStateStore(fileURL: fileURL).load()?.sessions.first?.projection == .completed)

        let replacement = makeLaunch(host: host, run: replacementRun, adapterID: "replacement")
        try await stalePlane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await stalePlane.run(replacement).outcome == .completed)
        #expect(await replacementAdapter.counts().launch == 1)
        #expect(await stalePlane.projection(for: host) == .completed)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restart adapter failure is normalized.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `restart adapter failure is normalized`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            failsRestart: true,
        )
        let plane =
            RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: reviewRegressionTestsMakeRunningState()))
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.adapterUnavailable) {
            _ = try await plane.restore(hostReference: "host-a", expectedContext: reviewRegressionTestsMakeContext())
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restart compatibility preserves caller cancellation.
    /// restore 호환성 확인 중 발생한 caller 취소를 adapter 오류로 정규화하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파와 restore claim·lease 미생성.
    /// - 사전 조건: persisted running session의 restart compatibility 확인이 cancellable delay에서 대기한다.
    /// - 기대 결과: restore는 CancellationError를 던지고 기존 running session은 비활성 lease로 유지된다.
    @Test
    func `restart compatibility preserves caller cancellation`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            restartDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(
            store: InMemoryRuntimeStateStore(state: reviewRegressionTestsMakeRunningState()),
        )
        try await plane.register(adapter)
        let restoreTask = Task {
            try await plane.restore(
                hostReference: "host-a",
                expectedContext: reviewRegressionTestsMakeContext(),
            )
        }
        for _ in 0 ..< 10000 {
            if await !adapter.receivedRestartBindings().isEmpty { break }
            await Task.yield()
        }

        restoreTask.cancel()

        await #expect(throws: CancellationError.self) { try await restoreTask.value }
        #expect(await plane.projection(for: "host-a") == .running)
        #expect(await plane.sessions["host-a"]?.lease.isActive == false)
        #expect(await plane.sessions["host-a"]?.stored.restorationClaim == nil)
        #expect(await adapter.receivedRestartBindings().count == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: persisted run blocks launch while compatibility check restores
    /// it.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `persisted run blocks launch while compatibility check restores it`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchDelay: .milliseconds(150),
            restartDelay: .milliseconds(100),
        )
        let plane =
            RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: reviewRegressionTestsMakeRunningState()))
        try await plane.register(adapter)
        let restoreTask = Task {
            try await plane.restore(
                hostReference: "host-a",
                expectedContext: reviewRegressionTestsMakeContext(),
            )
        }
        await adapter.waitForRestartBindingCount(1)
        let runTask = Task {
            try await runPolicyReady(
                plane,
                makeLaunch(host: "host-a", run: RuntimeRunReference("run-b"), adapterID: "sdk"),
            )
        }

        #expect(try await restoreTask.value == .restored)
        await #expect(throws: RuntimeHostError.activeRunExists) {
            _ = try await runTask.value
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restart binding includes persisted capability snapshot.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `restart binding includes persisted capability snapshot`() async throws {
        let context = boundedModelTestsMakeCanonicalContext()
        let stored = boundedModelTestsMakeRunningSession(
            host: "host-binding",
            run: RuntimeRunReference("run-binding"),
            context: context,
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
        ))
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: "host-binding", expectedContext: context) == .restored)
        #expect(await adapter.receivedRestartBindings().first?.capabilitySnapshot == .allSupported)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydrated restart binding receives validated execution context.
    /// 파일 저장 후 hydrate된 세션도 검증된 현재 실행 컨텍스트를 adapter에 전달하는지 검증한다.
    /// - 검증 내용: working directory, allowed roots, request context가 restart binding에 유지된다.
    /// - 사전 조건: 전체 실행 컨텍스트 fingerprint가 포함된 running snapshot이 파일 store에 저장되어 있다.
    /// - 기대 결과: restore는 성공하고 adapter는 caller가 제공한 full expected context를 수신한다.
    @Test
    func `hydrated restart binding receives validated execution context`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = boundedModelTestsMakeCanonicalContext()
        let stored = boundedModelTestsMakeRunningSession(
            host: "host-hydrated-binding",
            run: RuntimeRunReference("run-hydrated-binding"),
            context: context,
        )
        let store = RuntimeFileStateStore(fileURL: fileURL)
        try await store.seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await plane.register(adapter)

        #expect(try await plane.restore(
            hostReference: stored.externalAgentSessionReference,
            expectedContext: context,
        ) == .restored)
        let binding = try #require(await adapter.receivedRestartBindings().first)
        #expect(binding.contextPolicy.workingDirectory == context.workingDirectory)
        #expect(binding.contextPolicy.allowedRoots == context.allowedRoots)
        #expect(binding.contextPolicy.requestContext == context.requestContext)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restored run resumes provider event consumption.
    /// 호환 가능한 복원 뒤 provider event와 terminal result 소비를 명시적으로 재개하는지 검증한다.
    /// - 검증 내용: 복원된 run의 stream 호출, completed projection, artifact result 보존.
    /// - 사전 조건: running snapshot과 compatible adapter binding이 저장되어 있다.
    /// - 기대 결과: resume 경계가 provider 소비를 한 번 재개하고 terminal 결과를 반환한다.
    @Test
    func `restored run resumes provider event consumption`() async throws {
        let host = ExternalAgentSessionReference("host-resume-consumption")
        let run = RuntimeRunReference("run-resume-consumption")
        let context = finalReviewTestsMakeContext()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
        )
        let result = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://restored-result.json"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "restored-completed",
                kind: .completed,
            )]],
            terminalResultOverride: result,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        )))
        try await plane.register(adapter)

        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
        let resumed = try await plane.resumeRestoredRun(hostReference: host)

        #expect(resumed == result)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await adapter.counts().stream == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restored adapter failure repairs only its own resume claim.
    /// 실제 resumeRestoredRun의 adapter 오류 cleanup이 persistence conflict와 unavailable을 구분하면서 replacement owner를 보존하는지
    /// 검증한다.
    /// - 검증 내용: restore/resume claim owner token, interruptResumedRunOrRestoreClaim 경로, conflict/unavailable 저장 경계,
    /// exact lease recovery와 replacement owner 보존.
    /// - 사전 조건: compatible restored snapshot, event-stream creation failure, same-host replacement state, deterministic
    /// cleanup update counter가 구성되어 있다.
    /// - 기대 결과: conflict는 persistenceConflict, unavailable은 persistenceFailure를 반환하고 원래 claim owner만 local
    /// restored lease로 복구하며 replacement state를 지우지 않는다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `restored adapter failure repairs only its own resume claim`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let fixture = try await makeResumptionCleanupFixture(failure: failure)

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

    /// ATI-006-coordinate_external_agent_run_continuity: cross-plane host terminal wins over restoration heartbeat.
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
        let host = ExternalAgentSessionReference("host-heartbeat-terminal")
        let run = RuntimeRunReference("run-heartbeat-terminal")
        let context = finalReviewTestsMakeContext()
        let streamGate = RuntimeTestGate()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-terminal"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
        )
        try await RuntimeFileStateStore(fileURL: fileURL).seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let resumingPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await resumingPlane.register(adapter)
        #expect(try await resumingPlane.restore(hostReference: host, expectedContext: context) == .restored)
        let resume = Task { try await resumingPlane.resumeRestoredRun(hostReference: host) }
        await adapter.waitForEventStreamCount(1)

        let hostPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let terminal = try #require(try await hostPlane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        )))

        #expect(terminal.outcome == .completed)
        #expect(try await resume.value.outcome == .completed)
        await streamGate.open()
        #expect(await resumingPlane.projection(for: host) == .completed)
        #expect(await hostPlane.projection(for: host) == .completed)
        #expect(try await RuntimeFileStateStore(fileURL: fileURL).load()?.sessions.first?.restorationClaim == nil)
        #expect(await adapter.counts().stream == 1)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: heartbeat persistence failure preserves resume claim.
    /// provider 소비 중 heartbeat conflict와 저장 실패를 run interruption으로 오인하지 않는지 검증한다.
    /// - 검증 내용: persistenceConflict/persistenceFailure 구분, running projection과 재개 가능한 claim 보존.
    /// - 사전 조건: restored stream은 대기하고 첫 heartbeat renewal save가 실패한다.
    /// - 기대 결과: conflict는 persistenceConflict, unavailable은 persistenceFailure이며 다음 resume이 stream을 다시 연다.
    @Test(arguments: PersistenceBoundaryFailure.allCases)
    func `heartbeat persistence failure preserves resume claim`(
        failure: PersistenceBoundaryFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-persistence-failure")
        let run = RuntimeRunReference("run-heartbeat-persistence-failure")
        let context = finalReviewTestsMakeContext()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-persistence-failure"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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

    // MARK: - ATI-006-coordinate_external_agent_run_continuity

    /// ATI-006-coordinate_external_agent_run_continuity: typed terminal probe failure survives heartbeat conflict.
    /// renewal conflict 뒤 terminal probe의 persisted-state 오류가 heartbeat persistence 오류로 뭉개지지 않는지 검증한다.
    /// - 검증 내용: save #3 conflict, load #2 typed invalid/unsupported error, exact error, claim과 retryability.
    /// - 사전 조건: restored running session과 대기 provider stream이 구성되고 terminal probe load에 typed 오류가 주입된다.
    /// - 기대 결과: 원래 `invalidPersistedState` 또는 `unsupportedSchemaVersion`이 반환되고 running claim이 복구된다.
    @Test(arguments: HeartbeatProbeFailure.allCases)
    func `typed terminal probe failure survives heartbeat conflict`(
        failure: HeartbeatProbeFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-heartbeat-probe-\(failure.rawValue)")
        let run = RuntimeRunReference("run-heartbeat-probe-\(failure.rawValue)")
        let context = finalReviewTestsMakeContext()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-probe"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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

    /// ATI-006-coordinate_external_agent_run_continuity: cancellation wins over a visible restored terminal.
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
        let context = finalReviewTestsMakeContext()
        let streamGate = RuntimeTestGate()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-heartbeat-cancellation"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
        )
        let store = RuntimeFileStateStore(fileURL: fileURL)
        try await store.seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
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
        _ = try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))

        resume.cancel()

        await #expect(throws: CancellationError.self) { try await resume.value }
        #expect(await plane.projection(for: host) == .completed)
        #expect(try await store.load()?.sessions.first?.projection == .completed)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restored terminal result retries transient persistence
    /// failure.
    /// 복원 소비가 얻은 terminal 결과를 interruption으로 바꾸지 않고 동일 결과 저장만 재시도하는지 검증한다.
    /// - 검증 내용: 첫 finish save 실패 뒤 반환 결과, durable projection, artifact와 save 횟수.
    /// - 사전 조건: terminal-only restored run과 첫 save만 실패하는 state store가 있다.
    /// - 기대 결과: resume은 provider 결과를 반환하고 두 번째 save로 completed 상태를 지속한다.
    @Test
    func `restored terminal result retries transient persistence failure`() async throws {
        let host = ExternalAgentSessionReference("host-resume-finish-retry")
        let run = RuntimeRunReference("run-resume-finish-retry")
        let context = finalReviewTestsMakeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://restored-finish-retry.json"],
        )
        let capabilities = RuntimeCapabilities(
            discovery: .unsupported,
            eventStream: .unsupported,
            approval: .unsupported,
            cancellation: .unsupported,
            queuedInput: .unsupported,
            terminalResult: .supported,
            sameIdentityResume: .supported,
        )
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-finish-retry"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: capabilities,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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

    /// ATI-006-coordinate_external_agent_run_continuity: failed restored terminal persistence restores its claim.
    /// terminal 결과 저장이 두 번 실패해도 복원 claim을 잃지 않고 같은 control plane에서 다시 재개하는지 검증한다.
    /// - 검증 내용: persistenceFailure 전파, running projection 보존, 두 번째 resume 결과와 save 횟수.
    /// - 사전 조건: terminal-only restored run과 첫 두 save를 실패시키는 state store가 있다.
    /// - 기대 결과: 첫 resume 뒤 claim이 복구되고 두 번째 resume은 동일 completed 결과를 저장한다.
    @Test
    func `failed restored terminal persistence restores its claim`() async throws {
        let host = ExternalAgentSessionReference("host-resume-finish-double-failure")
        let run = RuntimeRunReference("run-resume-finish-double-failure")
        let context = finalReviewTestsMakeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://restored-finish-double-failure.json"],
        )
        let capabilities = RuntimeCapabilities(
            discovery: .unsupported,
            eventStream: .unsupported,
            approval: .unsupported,
            cancellation: .unsupported,
            queuedInput: .unsupported,
            terminalResult: .supported,
            sameIdentityResume: .supported,
        )
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-finish-double-failure"),
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: capabilities,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
        )
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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

    /// ATI-006-coordinate_external_agent_run_continuity: cancelling restored consumption preserves its claim.
    /// caller task 취소가 provider interruption으로 저장되지 않고 동일 run의 재개 가능성을 유지하는지 검증한다.
    /// - 검증 내용: CancellationError 전파, running projection 보존, 두 번째 resume의 stream 재개.
    /// - 사전 조건: compatible running snapshot과 지연된 provider event stream이 있다.
    /// - 기대 결과: 두 번의 caller cancellation 모두 durable interruption 없이 원래 취소로 종료된다.
    @Test
    func `cancelled restored consumption preserves its claim`() async throws {
        let host = ExternalAgentSessionReference("host-resume-cancelled")
        let run = RuntimeRunReference("run-resume-cancelled")
        let context = finalReviewTestsMakeContext()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-resume-cancelled"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
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
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: failed restored-run cleanup remains retryable.
    /// 복원 소비의 terminal 저장과 interruption 저장이 연속 실패해도 lease를 다시 소비할 수 있는지 검증한다.
    /// - 검증 내용: 두 번의 persistence failure 뒤 동일 restored run의 provider stream 재개.
    /// - 사전 조건: compatible running snapshot과 첫 두 save를 실패시키는 state store가 있다.
    /// - 기대 결과: 첫 resume은 persistenceFailure이고 두 번째 resume은 completed 결과를 반환한다.
    @Test
    func `restored run remains retryable after cleanup persistence failures`() async throws {
        let host = ExternalAgentSessionReference("host-resume-retry")
        let run = RuntimeRunReference("run-resume-retry")
        let context = finalReviewTestsMakeContext()
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-retry"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
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
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
            failingSaveNumbers: [2],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await adapter.counts().stream == 0)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: persisted rollback cannot resurrect a consumed resume claim.
    /// 다른 host 저장 실패가 진행 중인 복원 소비 claim을 되살려 중복 stream을 여는 경쟁을 차단한다.
    /// - 검증 내용: persistence lock 대기, 실패 rollback 뒤 claim 상태, 두 번째 resume 거부, stream 호출 횟수.
    /// - 사전 조건: 복원 claim을 가진 running session과 save 실패 gate, 소비 stream gate가 구성되어 있다.
    /// - 기대 결과: claim은 persistence mutation과 직렬화되고 provider stream은 한 번만 열린다.
    @Test
    func `failed concurrent persistence cannot resurrect resume claim`() async throws {
        let fixture = try await reviewerBlockerTestsMakeResumeClaimRace()

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
        let boundary = try await reviewerBlockerTestsWaitForResumeClaimBoundary(
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

    /// ATI-006-coordinate_external_agent_run_continuity: cancelled restore waiter cannot mint a claim.
    /// persistence lock을 기다리다 취소된 restore가 소유자 없는 restored lease를 발급하지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, inactive lease 보존, 같은 control plane의 restore 재시도.
    /// - 사전 조건: compatible running snapshot과 다른 host의 지연된 persistence mutation이 있다.
    /// - 기대 결과: 취소된 waiter는 claim을 만들지 않고 후속 restore가 restored 결과를 반환한다.
    @Test
    func `cancelled restore persistence waiter cannot mint a claim`() async throws {
        let host = ExternalAgentSessionReference("host-restore-waiter-cancelled")
        let run = RuntimeRunReference("run-restore-waiter-cancelled")
        let context = finalReviewTestsMakeContext()
        let saveGate = RuntimeTestGate()
        let stored = reviewerBlockerTestsMakeRunningSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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
        try await reviewerBlockerTestsWaitForPersistenceWaiters(1, on: plane)

        restore.cancel()
        await saveGate.open()

        _ = try await competingSave.value
        await #expect(throws: CancellationError.self) { try await restore.value }
        #expect(await plane.sessions[host]?.lease.isActive == false)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: cancelled resume waiter cannot mint a claim.
    /// persistence lock을 기다리다 취소된 resume이 소유자 없는 resuming lease나 provider stream을 만들지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, restored lease 보존, stream 미호출, 같은 control plane의 resume 재시도.
    /// - 사전 조건: restored claim과 다른 host의 지연된 persistence mutation, 소비 stream gate가 있다.
    /// - 기대 결과: 취소된 waiter는 claim을 전환하지 않고 후속 resume만 provider stream을 한 번 연다.
    @Test
    func `cancelled resume persistence waiter cannot mint a claim`() async throws {
        let fixture = try await reviewerBlockerTestsMakeResumeClaimRace()
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
        try await reviewerBlockerTestsWaitForPersistenceWaiters(1, on: fixture.plane)

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

    /// ATI-006-coordinate_external_agent_run_continuity: only compatible restart binding is restored.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `only compatible restart binding is restored`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let store = InMemoryRuntimeStateStore()
        try await store.seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [persistenceContractTestsMakeStoredSession()],
        ))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let restored = try await plane.restore(
            hostReference: host,
            expectedContext: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
        )
        let stalePlane = RuntimeControlPlane(store: store)
        try await stalePlane.register(adapter)
        let stale = try await stalePlane.restore(
            hostReference: host,
            expectedContext: RuntimeContextPolicy(
                branchReference: "other",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
        )

        #expect(restored == .restored)
        #expect(stale == .stale)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: stale hydrated session releases its host.
    /// 복원할 수 없는 file-hydrated 세션이 같은 host의 새 실행을 영구 차단하지 않는지 검증한다.
    /// - 검증 내용: context mismatch의 stale 판정, interrupted persistence, same-host relaunch 완료.
    /// - 사전 조건: provider handle이 있는 running snapshot과 다른 expected context가 주어진다.
    /// - 기대 결과: stale 세션은 terminal 상태로 정리되고 새 run이 같은 host에서 완료된다.
    @Test
    func `stale hydrated session releases its host`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeFileStateStore(fileURL: fileURL)
        try await store.seed(reviewRegressionTestsMakeRunningState())
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-b")
        let completed = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "replacement-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[completed]],
        )
        let plane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await plane.register(adapter)

        let stale = try await plane.restore(
            hostReference: host,
            expectedContext: RuntimeContextPolicy(
                branchReference: "other",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
        )
        let released = try #require(try await store.load()?.sessions.first)
        let replacement = makeLaunch(host: host, run: run, adapterID: "sdk")

        #expect(stale == .stale)
        #expect(released.projection == .interrupted)
        try await plane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await plane.run(replacement).outcome == .completed)
        #expect(await adapter.counts().launch == 1)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: restore rejects execution context mutations.
    /// 재시작 호환성 검사가 승인된 실행 컨텍스트 전체를 비교하는지 검증한다.
    /// - 검증 내용: working directory, allowed roots, request context 변경 시 stale 판정.
    /// - 사전 조건: provider handle과 전체 실행 컨텍스트 snapshot이 저장되어 있다.
    /// - 기대 결과: 변경된 컨텍스트는 adapter compatibility 호출 전에 복원에서 제외된다.
    @Test
    func `restore rejects execution context mutations`() async throws {
        let stored = finalBoundaryTestsMakeStored(
            host: "host-restore-policy",
            run: RuntimeRunReference("run-restore-policy"),
        )

        for context in mutatedExecutionContexts(from: finalBoundaryTestsMakeContext()) {
            let adapter = finalBoundaryTestsMakeAdapter()
            let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: finalBoundaryTestsMakeState([
                stored,
            ])))
            try await plane.register(adapter)

            #expect(try await plane.restore(
                hostReference: stored.externalAgentSessionReference,
                expectedContext: context,
            ) == .stale)
            #expect(await adapter.receivedRestartBindings().isEmpty)
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: capability snapshot mismatch cannot restore.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `capability snapshot mismatch cannot restore`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let capabilities = RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .supported,
            cancellation: .unknown,
            queuedInput: .supported,
            terminalResult: .supported,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[]],
        )
        let store = InMemoryRuntimeStateStore()
        try await store.seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [persistenceContractTestsMakeStoredSession()],
        ))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let result = try await plane.restore(
            hostReference: host,
            expectedContext: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
        )

        #expect(result == .stale)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: unavailable resume capability releases its host.
    /// 복원 capability가 불가한 file-hydrated 세션이 같은 host의 새 실행을 영구 차단하지 않는지 검증한다.
    /// - 검증 내용: typed capability 오류, interrupted persistence, same-host relaunch 완료.
    /// - 사전 조건: sameIdentityResume가 unknown 또는 unsupported인 running snapshot이 저장되어 있다.
    /// - 기대 결과: capability 오류 뒤 stale 예약이 정리되고 새 run이 같은 host에서 완료된다.
    @Test(arguments: [RuntimeCapabilityStatus.unknown, .unsupported])
    func `unavailable resume capability releases its host`(status: RuntimeCapabilityStatus) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let capabilities = reviewRegressionTestsMakeResumeCapabilities(status)
        let stored = reviewerBlockerTestsMakeRunningSession(
            host: "host-resume-unknown",
            run: RuntimeRunReference("run-resume-unknown"),
            context: reviewRegressionTestsMakeContext(),
            capabilities: capabilities,
        )
        let store = RuntimeFileStateStore(fileURL: fileURL)
        try await store.seed(RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let replacementRun = RuntimeRunReference("run-resume-replacement")
        let completed = makeEvent(
            host: stored.externalAgentSessionReference,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "resume-replacement-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[completed]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        try await reviewRegressionTestsExpectUnavailableResume(status, plane: plane, stored: stored)
        let released = try #require(try await store.load()?.sessions.first)
        let replacement = makeLaunch(
            host: stored.externalAgentSessionReference,
            run: replacementRun,
            adapterID: "sdk",
        )

        #expect(released.projection == .interrupted)
        try await plane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await plane.run(replacement).outcome == .completed)
        #expect(await adapter.counts().launch == 1)
        #expect(await plane.projection(for: stored.externalAgentSessionReference) == .completed)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: provider branch mismatch cannot restore.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `provider branch mismatch cannot restore`() async throws {
        let state = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [finalReviewTestsMakeStoredSession(providerBranch: .stable)],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            providerBranch: .preview,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: state))
        try await plane.register(adapter)

        #expect(try await plane
            .restore(hostReference: "host-a", expectedContext: finalReviewTestsMakeContext()) == .stale)
    }

    /// ATI-006-coordinate_external_agent_run_continuity: hydration rejects duplicate hosts and excessive sessions.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `hydration rejects duplicate hosts and excessive sessions`() async throws {
        let duplicate = storageBoundaryTestsMakeStored(host: "host-duplicate", run: RuntimeRunReference("run-a"))
        let duplicateState = storageBoundaryTestsMakeState([
            duplicate,
            storageBoundaryTestsMakeStored(host: "host-duplicate", run: RuntimeRunReference("run-b")),
        ])
        let duplicatePlane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: duplicateState))
        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await duplicatePlane.projectPrelaunch(
                makeLaunch(host: "new-host", run: RuntimeRunReference("new-run"), adapterID: "sdk"),
                as: .launchBlocked,
            )
        }

        let sessions = (0 ... RuntimeBoundaryLimits.persistedSessions).map {
            storageBoundaryTestsMakeStored(
                host: ExternalAgentSessionReference("host-\($0)"),
                run: RuntimeRunReference("run-\($0)"),
            )
        }
        let cappedPlane =
            RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState(sessions)))
        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await cappedPlane.projectPrelaunch(
                makeLaunch(host: "overflow", run: RuntimeRunReference("overflow"), adapterID: "sdk"),
                as: .launchBlocked,
            )
        }
    }

    /// ATI-006-coordinate_external_agent_run_continuity: custom store future schema fails closed during hydration.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `custom store future schema fails closed during hydration`() async throws {
        let future = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion + 1,
            sessions: [],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: future))

        await #expect(throws: RuntimeHostError.unsupportedSchemaVersion(future.schemaVersion)) {
            try await plane.projectPrelaunch(
                makeLaunch(host: "future-host", run: RuntimeRunReference("future-run"), adapterID: "sdk"),
                as: .launchBlocked,
            )
        }
    }

    // MARK: - ATI-006-project_external_agent_run_events

    /// ATI-006-project_external_agent_run_events: duplicate events mutate once and sequence gaps remain evidence.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `duplicate events mutate once and sequence gaps remain evidence`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let duplicate = makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "same", kind: .progress)
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[
                duplicate,
                duplicate,
                makeEvent(host: host, run: run, sequence: 3, idempotencyKey: "gap", kind: .completed),
            ]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        let evidence = await plane.eventEvidence(for: host)

        #expect(evidence == [
            .ignoredDuplicate(RuntimeIdempotencyKey("same")),
            .sequenceGap(expected: 2, received: 3),
        ])
        #expect(await plane.acceptedEventCount(for: host) == 2)
    }

    /// ATI-006-project_external_agent_run_events: unknown cancellation capability preserves nonterminal projection.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `unknown cancellation capability preserves nonterminal projection`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let capabilities = RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .unsupported,
            cancellation: .unknown,
            queuedInput: .unsupported,
            terminalResult: .supported,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: capabilities,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
            launchDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForLaunchCount(1)

        await #expect(throws: RuntimeHostError.capabilityUnknown(.cancellation)) {
            try await plane.requestCancellation(
                hostReference: host,
                operationID: RuntimeOperationID("cancel-1"),
            )
        }
        #expect(await plane.projection(for: host) == .launching)
        _ = try await task.value
        #expect(await adapter.counts().cancellation == 0)
    }

    /// ATI-006-project_external_agent_run_events: terminal gap records out of order without terminalizing.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal gap records out of order without terminalizing`() async throws {
        let host: ExternalAgentSessionReference = "host-gap"
        let run = RuntimeRunReference("run-gap")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchDelay: .milliseconds(100),
            eventStreamDelay: .milliseconds(500),
        )
        let plane = RuntimeControlPlane(store: RuntimeFileStateStore(
            fileURL: root.appendingPathComponent("runtime-state.json"),
        ))
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        try await waitForProjection(.launching, host: host, on: plane)

        let result = try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: run,
            sequence: 2,
        ))

        #expect(result == nil)
        #expect(await plane.projection(for: host) == .launching)
        #expect(try await task.value.outcome == .completed)
        let persisted = try #require(try await RuntimeFileStateStore(
            fileURL: root.appendingPathComponent("runtime-state.json"),
        ).load()?.sessions.first)
        #expect(persisted.eventEvidence.contains(.sequenceGap(expected: 1, received: 2)))
    }

    /// ATI-006-project_external_agent_run_events: host terminal before launch receipt preserves provider binding.
    /// launch receipt보다 먼저 저장된 host terminal과 뒤늦게 확인된 provider 시작 사실을 함께 보존한다.
    /// - 검증 내용: terminal 결과 우선순위, late receipt persistence, provider stream 미개방.
    /// - 사전 조건: provider launch가 receipt 반환 직전에 gate에서 대기하고 host terminal이 먼저 저장된다.
    /// - 기대 결과: run은 저장된 terminal 결과를 반환하고 provider handle은 같은 terminal session에 병합된다.
    @Test
    func `host terminal before launch receipt preserves provider binding`() async throws {
        let host: ExternalAgentSessionReference = "host-launch"
        let run = RuntimeRunReference("run-launch")
        let launchGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForLaunchCount(1)

        let terminal = try await plane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1),
        )
        await launchGate.open()

        #expect(terminal?.outcome == .completed)
        #expect(try await task.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
        #expect(await adapter.counts().stream == 0)
    }

    /// ATI-006-project_external_agent_run_events: cross-plane late receipt adopts the durable terminal.
    /// 다른 control plane이 먼저 저장한 terminal과 뒤늦은 provider receipt를 같은 host/run 결과로 수렴한다.
    /// - 검증 내용: file-backed receipt CAS conflict 이후 provider binding 병합, terminal projection 보존, exact launch lease 해제,
    /// replacement 실행.
    /// - 사전 조건: Plane A의 provider launch가 gate에서 대기하고 Plane B가 같은 file store에 동일 host/run completed terminal을 저장한다.
    /// - 기대 결과: Plane A는 completed를 반환하고 opaque-1을 durable terminal에 병합하며 원래 stream 없이 replacement만 한 번 실행된다.
    @Test
    func `cross-plane late receipt adopts durable terminal`() async throws {
        let fixture = makeCrossPlaneLateReceiptFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.providerPlane.register(fixture.originalAdapter)
        try await fixture.providerPlane.register(fixture.replacementAdapter)
        let originalTask = Task {
            try await runPolicyReady(
                fixture.providerPlane,
                makeLaunch(host: fixture.host, run: fixture.originalRun, adapterID: "original"),
            )
        }
        await fixture.originalAdapter.waitForLaunchCount(1)

        let hostPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fixture.fileURL))
        #expect(try await hostPlane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: fixture.host, run: fixture.originalRun, sequence: 1),
        )?.outcome == .completed)
        await fixture.launchGate.open()

        #expect(try await originalTask.value.outcome == .completed)
        let persistedState = try #require(try await RuntimeFileStateStore(fileURL: fixture.fileURL).load())
        let persisted = try #require(persistedState.sessions.first)
        #expect(persisted.runReference == fixture.originalRun)
        #expect(persisted.projection == .completed)
        #expect(persisted.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
        #expect(await fixture.originalAdapter.counts().stream == 0)

        let replacement = makeLaunch(host: fixture.host, run: fixture.replacementRun, adapterID: "replacement")
        try await fixture.providerPlane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await fixture.providerPlane.run(replacement).outcome == .completed)
        let originalLaunches = await fixture.originalAdapter.counts().launch
        let replacementLaunches = await fixture.replacementAdapter.counts().launch
        #expect(originalLaunches + replacementLaunches == 2)
    }

    /// ATI-006-project_external_agent_run_events: second receipt conflict adopts a durable replacement.
    /// 첫 receipt conflict에서 terminal을 채택한 뒤 retry 직전에 replacement가 저장되어도 stale receipt가 새 run을 덮지 않는지 검증한다.
    /// - 검증 내용: receipt와 cleanup의 연속 CAS conflict, 최신 durable state 채택, exact launch lease 해제, 후속 prelaunch 허용.
    /// - 사전 조건: update 3은 원래 terminal을, update 4부터 6은 새 run들을 저장하며 마지막 load는 replacement 또는 원래 terminal을 반환한다.
    /// - 기대 결과: 원래 run은 persistenceConflict를 반환하고 local/durable state는 최신 terminal과 inactive lease로 수렴한다.
    @Test(arguments: SecondReceiptConflictFinalState.allCases)
    func `second receipt conflict adopts a durable replacement`(
        finalState: SecondReceiptConflictFinalState,
    ) async throws {
        let fixture = makeSecondReceiptConflictFixture(finalState: finalState)
        let nextRun = RuntimeRunReference("run-second-receipt-conflict-next")
        try await fixture.plane.register(fixture.adapter)

        await #expect(throws: RuntimeHostError.persistenceConflict) {
            _ = try await runPolicyReady(
                fixture.plane,
                makeLaunch(host: fixture.host, run: fixture.originalRun, adapterID: "sdk"),
            )
        }

        let local = try #require(await fixture.plane.sessions[fixture.host])
        #expect(local.stored.runReference == fixture.expectedFinalRun)
        #expect(local.stored.providerInternalSessionReference == fixture.expectedFinalProvider)
        #expect(local.lease.isActive == false)
        #expect(await fixture.store.currentState()?.sessions == [fixture.expectedFinalTerminal])
        #expect(await fixture.store.updateCount == 6)
        #expect(await fixture.adapter.counts().launch == 1)

        let next = makeLaunch(host: fixture.host, run: nextRun, adapterID: "sdk")
        try await fixture.plane.projectPrelaunch(next, as: .policyReady)
        #expect(await fixture.plane.projection(for: fixture.host) == .policyReady)
    }

    /// ATI-006-project_external_agent_run_events: late launch reconciliation reserves the terminal host.
    /// host terminal 뒤 남은 launch receipt 조정이 끝날 때까지 같은 host의 replacement 실행을 차단한다.
    /// - 검증 내용: pending receipt 중 replacement 차단, late provider binding, 조정 후 host 재사용.
    /// - 사전 조건: 첫 launch가 receipt 반환 직전에 대기하고 host terminal이 먼저 저장된다.
    /// - 기대 결과: replacement는 provider를 시작하지 않고 거부되며 receipt 조정 뒤 정상 실행된다.
    @Test
    func `late launch reconciliation reserves the terminal host`() async throws {
        let host: ExternalAgentSessionReference = "host-launch-reconciliation"
        let originalRun = RuntimeRunReference("run-launch-reconciliation-original")
        let replacementRun = RuntimeRunReference("run-launch-reconciliation-replacement")
        let launchGate = RuntimeTestGate()
        let replacementCompleted = makeEvent(
            host: host,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "launch-reconciliation-replacement-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[replacementCompleted]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let originalTask = Task {
            try await runPolicyReady(
                plane,
                makeLaunch(host: host, run: originalRun, adapterID: "sdk"),
            )
        }
        await adapter.waitForLaunchCount(1)
        let replacement = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")

        #expect(try await plane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: host, run: originalRun, sequence: 1),
        )?.outcome == .completed)
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await plane.projectPrelaunch(replacement, as: .policyReady)
        }
        #expect(await adapter.counts().launch == 1)

        await launchGate.open()
        #expect(try await originalTask.value.outcome == .completed)
        let reconciled = try #require(await store.currentState()?.sessions.first)
        #expect(reconciled.runReference == originalRun)
        #expect(reconciled.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))

        try await plane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await plane.run(replacement).outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    /// ATI-006-project_external_agent_run_events: stored host terminal survives a late launch failure.
    /// launch 대기 중 지속된 같은 run의 host terminal이 뒤늦은 adapter 오류보다 우선하는지 검증한다.
    /// - 검증 내용: launch 실패 이후 반환 outcome과 durable terminal projection.
    /// - 사전 조건: launch가 gate에서 대기하고 host terminal 저장 뒤 adapter가 실패한다.
    /// - 기대 결과: run은 adapter 오류 대신 stored completed 결과를 반환한다.
    @Test
    func `stored host terminal survives a late launch failure`() async throws {
        let host: ExternalAgentSessionReference = "host-launch-failure-terminal"
        let run = RuntimeRunReference("run-launch-failure-terminal")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
            failsLaunchAfterGate: true,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForLaunchCount(1)

        let terminal = try await plane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1),
        )
        await launchGate.open()

        #expect(terminal?.outcome == .completed)
        #expect(try await task.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-project_external_agent_run_events: persisted terminal fallback releases the exact launch lease.
    /// 다른 control plane의 terminal을 launch 실패 fallback으로 수용한 plane이 replacement를 막지 않는지 검증한다.
    /// - 검증 내용: fallback 결과, exact launch lease 해제, 같은 host의 replacement 실행.
    /// - 사전 조건: 공유 file store에서 original launch가 대기하는 동안 다른 plane이 같은 run terminal을 저장한다.
    /// - 기대 결과: original은 completed로 수렴하고 동일 plane의 replacement run도 completed로 종료된다.
    @Test
    func `persisted terminal fallback releases the exact launch lease`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host: ExternalAgentSessionReference = "host-cross-plane-launch-failure"
        let originalRun = RuntimeRunReference("run-cross-plane-launch-failure")
        let replacementRun = RuntimeRunReference("run-cross-plane-launch-replacement")
        let launchGate = RuntimeTestGate()
        let failingAdapter = DeterministicRuntimeAdapter(
            id: "failing",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
            failsLaunchAfterGate: true,
        )
        let replacementCompleted = makeEvent(
            host: host,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "cross-plane-launch-replacement-completed",
            kind: .completed,
        )
        let replacementAdapter = DeterministicRuntimeAdapter(
            id: "replacement",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[replacementCompleted]],
        )
        let providerPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await providerPlane.register(failingAdapter)
        try await providerPlane.register(replacementAdapter)
        let originalTask = Task {
            try await runPolicyReady(
                providerPlane,
                makeLaunch(host: host, run: originalRun, adapterID: "failing"),
            )
        }
        await failingAdapter.waitForLaunchCount(1)

        let hostPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        #expect(try await hostPlane.ingestHostEvent(
            reviewerBlockerTestsMakeHostTerminal(host: host, run: originalRun, sequence: 1),
        )?.outcome == .completed)
        await launchGate.open()

        #expect(try await originalTask.value.outcome == .completed)
        let replacement = makeLaunch(host: host, run: replacementRun, adapterID: "replacement")
        try await providerPlane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await providerPlane.run(replacement).outcome == .completed)
        #expect(await providerPlane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: pending host terminal save wins over launch failure cleanup.
    /// persistence lock에서 저장 중인 host terminal을 뒤늦은 launch 오류 정리보다 우선한다.
    /// - 검증 내용: terminal save와 launch failure cleanup의 직렬화 이후 public·durable outcome 일치.
    /// - 사전 조건: host terminal save가 gate에서 대기하는 동안 adapter launch가 실패하고 cleanup이 대기한다.
    /// - 기대 결과: run은 adapter 오류 대신 저장된 completed 결과를 반환하고 projection도 completed를 유지한다.
    @Test
    func `pending host terminal save wins over queued launch failure cleanup`() async throws {
        let host: ExternalAgentSessionReference = "host-pending-terminal-launch-failure"
        let run = RuntimeRunReference("run-pending-terminal-launch-failure")
        let launchGate = RuntimeTestGate()
        let terminalSaveGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchGate: launchGate,
            failsLaunchAfterGate: true,
        )
        let store = InMemoryRuntimeStateStore(saveGates: [3: terminalSaveGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForLaunchCount(1)
        let hostTerminalTask = Task {
            try await plane.ingestHostEvent(
                reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1),
            )
        }
        await store.waitForSaveCount(3)

        await launchGate.open()
        try await reviewerBlockerTestsWaitForPersistenceWaiters(1, on: plane)
        await terminalSaveGate.open()

        #expect(try await hostTerminalTask.value?.outcome == .completed)
        #expect(try await runTask.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-project_external_agent_run_events: restored nonterminal session reserves its host.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `restored nonterminal session reserves its host`() async throws {
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let store = InMemoryRuntimeStateStore(state: reviewRegressionTestsMakeRunningState())
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        #expect(try await plane
            .restore(hostReference: "host-a", expectedContext: reviewRegressionTestsMakeContext()) == .restored)
        await #expect(throws: RuntimeHostError.activeRunExists) {
            _ = try await runPolicyReady(plane, makeLaunch(
                host: "host-a",
                run: RuntimeRunReference("run-b"),
                adapterID: "sdk",
            ))
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-project_external_agent_run_events: terminal result must correlate to the active run.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal result must correlate to the active run`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultOverride: RuntimeResult(
                runReference: RuntimeRunReference("wrong-run"),
                outcome: .completed,
                artifactReferences: [],
            ),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await runPolicyReady(plane, makeLaunch(
                host: "host-a",
                run: RuntimeRunReference("run-a"),
                adapterID: "terminal",
            ))
        }
    }

    /// ATI-006-project_external_agent_run_events: streaming terminal result must correlate to the active run.
    /// 저장된 terminal projection이 provider 상관관계 위반을 성공으로 숨기지 않는지 검증한다.
    /// - 검증 내용: streaming terminal event 뒤 잘못된 runReference를 반환한 terminalResult 오류 전파.
    /// - 사전 조건: event stream은 현재 run을 완료하고 terminalResult는 다른 run을 반환한다.
    /// - 기대 결과: stored terminal fallback 대신 malformedAdapterResponse가 반환된다.
    @Test
    func `streaming terminal result must correlate to the active run`() async throws {
        let host: ExternalAgentSessionReference = "host-stream-correlation"
        let run = RuntimeRunReference("run-stream-correlation")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "completed",
                kind: .completed,
            )]],
            terminalResultOverride: RuntimeResult(
                runReference: RuntimeRunReference("wrong-run"),
                outcome: .completed,
                artifactReferences: [],
            ),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
    }

    /// ATI-006-project_external_agent_run_events: streaming terminal result outcome must match the terminal event.
    /// provider terminal event와 terminalResult의 outcome 불일치를 저장 projection으로 숨기지 않는지 검증한다.
    /// - 검증 내용: 같은 run의 completed event 뒤 failed terminalResult가 반환될 때의 semantic 오류 전파.
    /// - 사전 조건: event stream은 completed를 지속하고 terminalResult는 artifact를 포함한 failed를 반환한다.
    /// - 기대 결과: malformedAdapterResponse가 반환되고 durable completed projection은 유지된다.
    @Test
    func `streaming terminal result outcome must match the terminal event`() async throws {
        let host: ExternalAgentSessionReference = "host-stream-outcome-correlation"
        let run = RuntimeRunReference("run-stream-outcome-correlation")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "completed",
                kind: .completed,
            )]],
            terminalResultOverride: RuntimeResult(
                runReference: run,
                outcome: .failed,
                artifactReferences: ["artifact://failure.json"],
                failure: RuntimeAdapterFailure(
                    kind: .sdkException,
                    diagnosticCode: RuntimeDiagnosticCode("provider_failed"),
                ),
            ),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: late provider event cannot reuse a replacement terminal.
    /// 이전 run의 지연된 stream이 replacement run의 terminal 결과를 자신의 결과로 반환하지 않는지 검증한다.
    /// - 검증 내용: late event의 run 상관관계 오류와 replacement terminal projection 보존.
    /// - 사전 조건: replacement terminal이 복원된 coordinator에 이전 run의 stale consumer가 재진입한다.
    /// - 기대 결과: 이전 run은 malformedAdapterResponse로 끝나고 새 run의 terminal 상태는 유지된다.
    @Test
    func `late provider event cannot reuse a replacement terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-stream-replacement"
        let oldRun = RuntimeRunReference("run-stream-old")
        let replacementRun = RuntimeRunReference("run-stream-replacement")
        let oldAdapter = DeterministicRuntimeAdapter(
            id: "old-sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: oldRun,
                sequence: 1,
                idempotencyKey: "old-completed",
                kind: .completed,
            )]],
        )
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("replacement-handle"),
            runReference: replacementRun,
            adapterID: RuntimeAdapterID("replacement-terminal"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .terminalOnly,
            storedContext: RuntimeStoredContext(contextPolicy: finalReviewTestsMakeContext()),
            projection: .completed,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        )))
        try await plane.register(oldAdapter)
        try await plane.hydrateIfNeeded()
        #expect(await plane.projection(for: host) == .completed)
        let staleReceipt = RuntimeLaunchReceipt(
            runReference: oldRun,
            providerInternalSessionReference: ProviderInternalSessionReference("old-handle"),
        )

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.consume(staleReceipt, from: oldAdapter, host: host)
        }
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: terminal-only adapter completes without opening an event stream.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal-only adapter completes without opening an event stream`() async throws {
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, makeLaunch(
            host: "host-a",
            run: RuntimeRunReference("run-a"),
            adapterID: "terminal",
        ))

        #expect(result.outcome == .completed)
        #expect(await adapter.counts().stream == 0)
    }

    /// ATI-006-project_external_agent_run_events: stored host terminal survives terminal-result failure.
    /// terminal-only provider 조회 실패보다 먼저 지속된 host terminal 결과를 우선하는지 검증한다.
    /// - 검증 내용: terminalResult 오류 이후 반환 outcome과 durable terminal projection.
    /// - 사전 조건: terminalResult가 gate 뒤 실패하고 그 전에 host interrupted event가 저장된다.
    /// - 기대 결과: run은 adapter 오류 대신 stored interrupted 결과를 반환한다.
    @Test
    func `stored host terminal survives terminal-result failure`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-result-failure"
        let run = RuntimeRunReference("run-terminal-result-failure")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
            failsTerminalResult: true,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "terminal"))
        }
        await adapter.waitForTerminalResultCount(1)

        let terminal = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-terminal-result-failure"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-terminal-result-failure"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))
        await resultGate.open()

        #expect(terminal?.outcome == .interrupted)
        #expect(try await task.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: cross-plane host terminal wins over provider finish CAS.
    /// 다른 control plane이 저장한 같은 run의 terminal을 stale provider 결과로 덮지 않고 수렴하는지 검증한다.
    /// - 검증 내용: provider 결과 반환, durable terminal 우선순위, 양쪽 control plane projection.
    /// - 사전 조건: 공유 file store에서 provider terminalResult가 gate에 대기하는 동안 host terminal이 저장된다.
    /// - 기대 결과: stale finish CAS는 persistenceFailure 대신 durable interrupted 결과로 수렴한다.
    @Test
    func `cross-plane host terminal wins over provider finish CAS`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let host: ExternalAgentSessionReference = "host-provider-finish-cas"
        let run = RuntimeRunReference("run-provider-finish-cas")
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
        )
        let providerPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await providerPlane.register(adapter)
        let task = Task {
            try await runPolicyReady(providerPlane, makeLaunch(host: host, run: run, adapterID: "terminal"))
        }
        await adapter.waitForTerminalResultCount(1)

        let hostPlane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        let terminal = try await hostPlane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-provider-finish-cas"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-provider-finish-cas"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))
        await resultGate.open()

        #expect(terminal?.outcome == .interrupted)
        #expect(try await task.value.outcome == .interrupted)
        #expect(await providerPlane.projection(for: host) == .interrupted)
        #expect(await hostPlane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: retry CAS converges to a newly durable terminal.
    /// 첫 durable 조회 뒤 저장된 같은 run terminal을 두 번째 stale finish CAS 실패 후 다시 수렴하는지 검증한다.
    /// - 검증 내용: provider metadata 보존, completed projection, retry CAS 경쟁 처리.
    /// - 사전 조건: 첫 finish update는 실패하고 retry update가 대기하는 동안 같은 outcome terminal이 저장된다.
    /// - 기대 결과: caller는 persistenceFailure 대신 원래 provider result를 받고 active lease가 해제된다.
    @Test
    func `retry CAS converges to a newly durable terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-finish-second-cas"
        let run = RuntimeRunReference("run-finish-second-cas")
        let store = DeterministicHostMutationRuntimeStateStore(
            failingUpdateNumbers: [4],
        )
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://second-cas.json"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultOverride: expected,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await runPolicyReady(
                plane,
                makeLaunch(host: host, run: run, adapterID: "terminal"),
            )
        }
        #expect(await plane.projection(for: host) == .running)
    }

    /// ATI-006-project_external_agent_run_events: cancellation wins during persisted finish convergence.
    /// unavailable finish persistence가 conflict 전용 read-repair로 잘못 진입하지 않는지 검증한다.
    /// - 검증 내용: finish 저장 실패의 typed persistenceFailure와 local running 상태 보존.
    /// - 사전 조건: provider finish 저장이 unavailable로 실패하고 별도 durable terminal이 준비되어 있다.
    /// - 기대 결과: storage failure는 재시도하지 않고 원래 오류를 반환하며 local session은 running으로 남는다.
    @Test
    func `cancellation wins during persisted finish convergence`() async throws {
        let host: ExternalAgentSessionReference = "host-finish-convergence-cancellation"
        let run = RuntimeRunReference("run-finish-convergence-cancellation")
        let store = InMemoryRuntimeStateStore(
            failingSaveNumbers: [4],
        )
        let resultGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultGate: resultGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "terminal"))
        }
        await adapter.waitForTerminalResultCount(1)
        let running = try #require(await store.currentState()?.sessions.first)
        let terminal = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [running.withProjection(.completed)],
        )
        await store.replaceState(terminal)
        await resultGate.open()
        await #expect(throws: RuntimeHostError.persistenceFailure) { try await task.value }
        #expect(await plane.projection(for: host) == .running)
    }

    /// ATI-006-project_external_agent_run_events: cancellation wins during provider finish persistence.
    /// provider terminal 저장이 대기하는 동안 전달된 caller 취소가 저장 성공보다 우선하는지 검증한다.
    /// - 검증 내용: finish save suspension 뒤 CancellationError 전파와 durable terminal 보존.
    /// - 사전 조건: terminal-only provider 결과의 finish save가 gate에서 대기한다.
    /// - 기대 결과: 저장은 완료되지만 취소된 caller는 terminal 성공 대신 CancellationError를 받는다.
    @Test
    func `cancellation wins during provider finish persistence`() async throws {
        let host: ExternalAgentSessionReference = "host-finish-persistence-cancellation"
        let run = RuntimeRunReference("run-finish-persistence-cancellation")
        let saveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [4: saveGate])
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "terminal"))
        }
        await store.waitForSaveCount(4)

        task.cancel()
        await saveGate.open()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await store.currentState()?.sessions.first?.projection == .completed)
    }

    /// ATI-006-project_external_agent_run_events: streaming terminal event preserves provider result metadata.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: terminal event 이후 provider terminal result의 artifact metadata 반환.
    /// - 사전 조건: event stream과 terminal result를 모두 지원하는 adapter가 구성되어 있다.
    /// - 기대 결과: terminal projection을 유지하면서 provider artifact reference가 호출자에게 전달된다.
    @Test
    func `streaming terminal event preserves provider result metadata`() async throws {
        let host = ExternalAgentSessionReference("host-stream-result")
        let run = RuntimeRunReference("run-stream-result")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "completed",
                kind: .completed,
            )]],
            terminalResultOverride: RuntimeResult(
                runReference: run,
                outcome: .completed,
                artifactReferences: ["artifact://result.json"],
            ),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))

        #expect(result.outcome == .completed)
        #expect(result.artifactReferences == ["artifact://result.json"])
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: stored provider terminal survives terminal-result failure.
    /// stream terminal event가 지속된 뒤 provider 결과 조회 오류가 terminal 상태를 뒤집지 않는지 검증한다.
    /// - 검증 내용: streaming terminalResult 오류 이후 반환 outcome과 durable terminal projection.
    /// - 사전 조건: provider completed event 저장 뒤 terminalResult 조회가 실패한다.
    /// - 기대 결과: run은 adapter 오류 대신 stored completed 결과를 반환한다.
    @Test
    func `stored provider terminal survives terminal-result failure`() async throws {
        let host = ExternalAgentSessionReference("host-stream-result-failure")
        let run = RuntimeRunReference("run-stream-result-failure")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "completed",
                kind: .completed,
            )]],
            failsTerminalResult: true,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let result = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))

        #expect(result.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: stored host terminal survives provider stream failure.
    /// provider stream 생성 또는 iteration 실패보다 이미 지속된 host terminal 결과를 우선하는지 검증한다.
    /// - 검증 내용: stream failure phase별 반환 outcome과 durable terminal projection.
    /// - 사전 조건: provider stream이 gate 뒤 실패하고 그 전에 host interrupted event가 저장된다.
    /// - 기대 결과: run은 adapter 오류 대신 stored interrupted 결과를 반환한다.
    @Test(arguments: [
        DeterministicRuntimeAdapter.EventStreamFailure.creation,
        .iteration,
    ])
    func `stored host terminal survives provider stream failure`(
        failure: DeterministicRuntimeAdapter.EventStreamFailure,
    ) async throws {
        let host = ExternalAgentSessionReference("host-stream-failure-\(failure)")
        let run = RuntimeRunReference("run-stream-failure-\(failure)")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
            eventStreamFailure: failure,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)

        let terminal = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-stream-failure"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-stream-failure"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))
        await streamGate.open()

        #expect(terminal?.outcome == .interrupted)
        #expect(try await task.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: pending host terminal wins over a late provider event.
    /// provider event admission이 persistence lock 뒤에서 재개되어도 같은 run의 durable host terminal을 우선하는지 검증한다.
    /// - 검증 내용: host terminal 저장 중 도착한 provider event 이후의 run outcome과 durable projection.
    /// - 사전 조건: host terminal save가 gate에서 대기하는 동안 provider progress event가 persistence queue에 진입한다.
    /// - 기대 결과: run은 admission 오류 대신 stored completed 결과를 반환한다.
    @Test
    func `pending host terminal wins over a late provider event`() async throws {
        let host: ExternalAgentSessionReference = "host-pending-terminal-provider-event"
        let run = RuntimeRunReference("run-pending-terminal-provider-event")
        let streamGate = RuntimeTestGate()
        let saveGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "late-provider-progress",
                kind: .progress,
            )]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore(saveGates: [4: saveGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)
        let hostTerminalTask = Task {
            try await plane.ingestHostEvent(
                reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1),
            )
        }
        await store.waitForSaveCount(4)

        await streamGate.open()
        try await reviewerBlockerTestsWaitForPendingPersistenceMutations(2, host: host, on: plane)
        await saveGate.open()

        #expect(try await hostTerminalTask.value?.outcome == .completed)
        #expect(try await runTask.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: transient finish persistence failure retries terminal result.
    /// provider terminal 결과를 확보한 뒤 첫 저장만 실패해도 interrupted로 덮지 않는지 검증한다.
    /// - 검증 내용: 동일 terminal result의 persistence 재시도와 completed projection 보존.
    /// - 사전 조건: terminal-only adapter가 completed 결과를 반환하고 finish save #4만 실패한다.
    /// - 기대 결과: 재시도 저장이 성공하고 public run과 durable projection 모두 completed로 수렴한다.
    @Test
    func `transient finish persistence failure retries terminal result`() async throws {
        let host: ExternalAgentSessionReference = "host-transient-finish-persistence"
        let run = RuntimeRunReference("run-transient-finish-persistence")
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://finish-retry.json"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            terminalResultOverride: expected,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [4])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await runPolicyReady(
                plane,
                makeLaunch(host: host, run: run, adapterID: "terminal"),
            )
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.saveCount == 4)
    }

    /// ATI-006-project_external_agent_run_events: failed finish persistence releases its active claim.
    /// provider terminal 결과 저장이 두 번 실패해도 같은 control plane에서 persisted run을 복원하는지 검증한다.
    /// - 검증 내용: persistenceFailure 전파, running projection 보존, restore와 resume 결과.
    /// - 사전 조건: resumable terminal-only adapter와 finish save #4, #5를 실패시키는 state store가 있다.
    /// - 기대 결과: active lease가 복구되어 restore가 성공하고 resume이 동일 completed 결과를 저장한다.
    @Test
    func `failed finish persistence releases its active claim`() async throws {
        let host: ExternalAgentSessionReference = "host-finish-double-persistence"
        let run = RuntimeRunReference("run-finish-double-persistence")
        let context = finalReviewTestsMakeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://finish-double-persistence.json"],
        )
        let capabilities = RuntimeCapabilities(
            discovery: .unsupported,
            eventStream: .unsupported,
            approval: .unsupported,
            cancellation: .unsupported,
            queuedInput: .unsupported,
            terminalResult: .supported,
            sameIdentityResume: .supported,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "terminal",
            transport: .processJSONL,
            capabilities: capabilities,
            eventsByLaunch: [[]],
            terminalResultOverride: expected,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [4, 5])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: run,
            adapterID: RuntimeAdapterID("terminal"),
            contextPolicy: context,
            input: RuntimeSensitiveInput("not persisted"),
        )

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await runPolicyReady(plane, request)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.saveCount == 4)
    }

    /// ATI-006-project_external_agent_run_events: transient terminal event persistence failure retries the event.
    /// provider terminal event의 첫 저장 실패가 실제 outcome을 interrupted로 덮지 않는지 검증한다.
    /// - 검증 내용: 동일 terminal event의 persistence 재시도와 provider artifact metadata 보존.
    /// - 사전 조건: SDK adapter가 completed event와 artifact result를 반환하고 event save #4만 실패한다.
    /// - 기대 결과: event 저장 재시도가 성공하고 public run과 durable projection 모두 completed로 수렴한다.
    @Test
    func `transient terminal event persistence failure retries the event`() async throws {
        let host: ExternalAgentSessionReference = "host-transient-terminal-event-persistence"
        let run = RuntimeRunReference("run-transient-terminal-event-persistence")
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://terminal-event-retry.json"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-event-retry",
                kind: .completed,
            )]],
            terminalResultOverride: expected,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [4])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await runPolicyReady(
                plane,
                makeLaunch(host: host, run: run, adapterID: "sdk"),
            )
        }
        #expect(await plane.projection(for: host) == .interrupted)
        #expect(await store.saveCount == 5)
    }

    /// ATI-006-project_external_agent_run_events: failed terminal event persistence releases its active claim.
    /// provider terminal event 저장이 두 번 실패해도 같은 control plane에서 persisted run을 복원하는지 검증한다.
    /// - 검증 내용: persistenceFailure 전파, running projection 보존, restore와 resume 결과.
    /// - 사전 조건: resumable SDK adapter와 terminal event save #4, #5를 실패시키는 state store가 있다.
    /// - 기대 결과: consuming lease가 복구되어 restore가 성공하고 resume이 동일 completed 결과를 저장한다.
    @Test
    func `failed terminal event persistence releases its active claim`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-event-double-persistence"
        let run = RuntimeRunReference("run-terminal-event-double-persistence")
        let context = finalReviewTestsMakeContext()
        let expected = RuntimeResult(
            runReference: run,
            outcome: .completed,
            artifactReferences: ["artifact://terminal-event-double-persistence.json"],
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "terminal-event-double-persistence",
                kind: .completed,
            )]],
            terminalResultOverride: expected,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [4, 5])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = RuntimeLaunchRequest(
            externalAgentSessionReference: host,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            contextPolicy: context,
            input: RuntimeSensitiveInput("not persisted"),
        )

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await runPolicyReady(plane, request)
        }
        #expect(await plane.projection(for: host) == .running)
        #expect(await adapter.counts().launch == 1)
    }

    /// ATI-006-project_external_agent_run_events: bind persistence failure interrupts before event projection.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `bind persistence failure interrupts before event projection`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        #expect(await plane.acceptedEventCount(for: host) == 0)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: host-sourced adapter event is rejected.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host-sourced adapter event is rejected`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let event = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("provider-1"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("done"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[event]])
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
    }

    /// ATI-006-project_external_agent_run_events: terminal stored session is not restored.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal stored session is not restored`() async throws {
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane =
            RuntimeControlPlane(
                store: InMemoryRuntimeStateStore(state: reviewRegressionTestsMakeState(projection: .completed)),
            )
        try await plane.register(adapter)

        #expect(try await plane
            .restore(hostReference: "host-a", expectedContext: reviewRegressionTestsMakeContext()) == .stale)
    }

    /// ATI-006-project_external_agent_run_events: terminal event rejects operations while persistence is pending.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal event rejects operations while persistence is pending`() async throws {
        let host: ExternalAgentSessionReference = "host-a"
        let run = RuntimeRunReference("run-a")
        let store = InMemoryRuntimeStateStore(saveDelays: [3: .milliseconds(100)])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        let runTask = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await store.waitForSaveCount(3)
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        #expect(try await runTask.value.outcome == .completed)
        #expect(await adapter.counts().cancellation == 0)
    }

    /// ATI-006-project_external_agent_run_events: overlapping terminal transitions retain operation exclusion.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 같은 host의 terminal transition 하나가 종료되어도 남은 transition이 operation admission을 차단한다.
    /// - 사전 조건: 실행 중인 세션에 겹친 terminal transition 두 개가 등록되어 있다.
    /// - 기대 결과: 첫 transition 종료 뒤 cancellation은 invalidEvent이고 adapter는 호출되지 않는다.
    @Test
    func `overlapping terminal transitions retain operation exclusion`() async throws {
        let host: ExternalAgentSessionReference = "host-overlapping-terminal"
        let run = RuntimeRunReference("run-overlapping-terminal")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let saveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [4: saveGate])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)
        let firstTerminal = reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1)
        let secondTerminal = reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 2)
        let firstTask = Task { try await plane.ingestHostEvent(firstTerminal) }
        await store.waitForSaveCount(4)
        let secondTask = Task { try await plane.ingestHostEvent(secondTerminal) }
        try await reviewerBlockerTestsWaitForPendingPersistenceMutations(2, host: host, on: plane)

        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        #expect(await adapter.counts().cancellation == 0)

        await saveGate.open()
        _ = try await firstTask.value
        _ = await secondTask.result
        runTask.cancel()
        _ = await runTask.result
    }

    /// ATI-006-project_external_agent_run_events: persisted terminal session rejects new operations during
    /// reconciliation.
    /// terminal projection과 reconciliation lease를 분리해 종료된 run에 새 provider operation을 보내지 않는지 검증한다.
    /// - 검증 내용: approval, queued input, cancellation의 invalidEvent 및 adapter 미호출.
    /// - 사전 조건: host terminal event가 저장됐지만 consuming lease reconciliation은 대기 중이다.
    /// - 기대 결과: 세 operation은 adapter 호출 전에 거부되고 terminal projection은 유지된다.
    @Test
    func `persisted terminal session rejects new operations during reconciliation`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-operations"
        let run = RuntimeRunReference("run-terminal-operations")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)

        _ = try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1))
        #expect(await plane.projection(for: host) == .completed)

        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.respondToApproval(
                hostReference: host,
                requestID: RuntimeApprovalRequestID("approval"),
                operationID: RuntimeOperationID("approve"),
            )
        }
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.enqueueInput(
                hostReference: host,
                operationID: RuntimeOperationID("input"),
                input: RuntimeSensitiveInput("not persisted"),
            )
        }
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.requestCancellation(
                hostReference: host,
                operationID: RuntimeOperationID("cancel"),
            )
        }

        let counts = await adapter.counts()
        #expect(counts.approval == 0)
        #expect(counts.input == 0)
        #expect(counts.cancellation == 0)
        #expect(await plane.projection(for: host) == .completed)

        await streamGate.open()
        #expect(try await runTask.value.outcome == .completed)
    }

    /// ATI-006-project_external_agent_run_events: stale sequence is evidence and cannot move projection backward.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `stale sequence is evidence and cannot move projection backward`() async throws {
        let host = ExternalAgentSessionReference("host-a")
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[
                makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "one", kind: .progress),
                makeEvent(host: host, run: run, sequence: 0, idempotencyKey: "stale", kind: .progress),
                makeEvent(host: host, run: run, sequence: 2, idempotencyKey: "done", kind: .completed),
            ]],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))

        #expect(await plane.eventEvidence(for: host) == [
            .staleSequence(lastAccepted: 1, received: 0),
        ])
        #expect(await plane.acceptedEventCount(for: host) == 2)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: host terminal uses an independent sequence cursor.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host terminal uses an independent sequence cursor`() async throws {
        let host: ExternalAgentSessionReference = "host-source-cursor"
        let run = RuntimeRunReference("run-source-cursor")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)
        _ = try await plane.accept(
            makeEvent(host: host, run: run, sequence: 10, idempotencyKey: "provider-10", kind: .progress),
            host: host,
            expectedSource: .provider,
        )

        let result = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))
        let persisted = try #require(await store.currentState()?.sessions.first)

        #expect(result?.outcome == .interrupted)
        #expect(persisted.lastSequence == 10)
        #expect(persisted.acceptedEventCount == 1)
        #expect(persisted.processedEventCount == 1)
        task.cancel()
    }

    /// ATI-006-project_external_agent_run_events: host event accounting survives hydration independently.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host event accounting survives hydration independently`() async throws {
        let host: ExternalAgentSessionReference = "host-source-hydration"
        let run = RuntimeRunReference("run-source-hydration")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)
        _ = try await plane.ingestHostEvent(sourceIsolationTestsMakeHostProgress(host: host, run: run, sequence: 1))

        let savesBeforeFreshEvent = await store.saveCount
        let freshPlane = RuntimeControlPlane(store: store)
        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await freshPlane.ingestHostEvent(sourceIsolationTestsMakeHostProgress(
                host: host,
                run: run,
                sequence: 2,
            ))
        }

        #expect(await freshPlane.projection(for: host) == .eventProjected)
        #expect(await store.saveCount == savesBeforeFreshEvent)
        task.cancel()
    }

    /// ATI-006-project_external_agent_run_events: persisted event identity evidence is bounded.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `persisted event identity evidence is bounded`() async throws {
        let host: ExternalAgentSessionReference = "host-bounded"
        let run = RuntimeRunReference("run-bounded")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)
        for sequence in 1 ... 300 {
            _ = try await plane.ingestHostEvent(boundedModelTestsMakeHostProgress(
                host: host,
                run: run,
                sequence: UInt64(sequence),
            ))
        }
        let session = try #require(await store.currentState()?.sessions.first)

        #expect(session.acceptedIdempotencyKeys.count <= 256)
        task.cancel()
    }

    /// ATI-006-project_external_agent_run_events: oversized provider event identity is rejected.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `oversized provider event identity is rejected`() async throws {
        let host: ExternalAgentSessionReference = "host-oversized"
        let run = RuntimeRunReference("run-oversized")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(1),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)
        let event = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID(String(repeating: "x", count: 257)),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("one"),
            timestamp: .now,
            externalAgentSessionReference: host,
            runReference: run,
            kind: .progress,
        )

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.ingestHostEvent(event)
        }
        task.cancel()
    }

    /// ATI-006-project_external_agent_run_events: invalid host flood is rejected before persistence admission.
    /// 저장이 지연된 동안 경계를 초과한 host event가 mutation queue를 무제한 점유하지 않는지 검증한다.
    /// - 검증 내용: invalid host별 pending mutation과 persistence waiter가 생성되지 않는다.
    /// - 사전 조건: 하나의 정상 prelaunch save가 gate에서 대기하고 다수의 oversized host event가 동시에 도착한다.
    /// - 기대 결과: invalid event는 모두 malformed로 종료되고 queue에는 정상 저장 작업만 남는다.
    @Test
    func `invalid host flood is rejected before persistence admission`() async throws {
        let saveGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(saveGates: [1: saveGate])
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let prelaunchTask = Task {
            try await plane.projectPrelaunch(
                makeLaunch(host: "host-valid", run: RuntimeRunReference("run-valid"), adapterID: "sdk"),
                as: .policyReady,
            )
        }
        await store.waitForSaveCount(1)

        let invalidTasks = (0 ..< 32).map { index in
            Task {
                try await plane.ingestHostEvent(RuntimeEventEnvelope(
                    source: .host,
                    providerEventID: ProviderEventID("invalid-\(index)"),
                    sequence: 1,
                    idempotencyKey: RuntimeIdempotencyKey("invalid-\(index)"),
                    timestamp: Date(timeIntervalSince1970: 1),
                    externalAgentSessionReference: ExternalAgentSessionReference(
                        String(repeating: "x", count: RuntimeBoundaryLimits.identifierScalars + 1) + "-\(index)",
                    ),
                    runReference: RuntimeRunReference("run-invalid-\(index)"),
                    kind: .progress,
                ))
            }
        }
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        let invalidPendingHosts = await plane.pendingPersistenceMutations.keys.count(where: { $0 != "host-valid" })
        let waiterCount = await plane.persistenceMutationWaiters.count
        await saveGate.open()
        try await prelaunchTask.value
        for task in invalidTasks {
            await #expect(throws: RuntimeHostError.malformedAdapterResponse) { try await task.value }
        }

        #expect(invalidPendingHosts == 0)
        #expect(waiterCount == 0)
    }

    /// ATI-006-project_external_agent_run_events: persisted event evidence deeply validates associated identifiers.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `persisted event evidence deeply validates associated identifiers`() async throws {
        let oversized = RuntimeIdempotencyKey(String(
            repeating: "x",
            count: RuntimeBoundaryLimits.identifierScalars + 1,
        ))
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: "host-evidence-bound",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-evidence-bound"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: boundedModelTestsMakeCanonicalContext()),
            projection: .running,
            lastSequence: 0,
            eventEvidence: [.ignoredDuplicate(oversized)],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        )))

        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            try await plane.projectPrelaunch(
                makeLaunch(
                    host: "other-host",
                    run: RuntimeRunReference("other-run"),
                    adapterID: "sdk",
                ),
                as: .launchBlocked,
            )
        }
    }

    /// ATI-006-project_external_agent_run_events: fresh control plane reserves persisted nonterminal host before
    /// launch.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `fresh control plane reserves persisted nonterminal host before launch`() async throws {
        let store = InMemoryRuntimeStateStore(state: finalContractTestsMakeStoredState(projection: .running))
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.activeRunExists) {
            _ = try await runPolicyReady(
                plane,
                makeLaunch(host: "host-a", run: RuntimeRunReference("run-b"), adapterID: "sdk"),
            )
        }
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-project_external_agent_run_events: invalid running snapshot does not reserve its host.
    /// provider handle이 없는 running snapshot을 hydration 단계에서 원자적으로 거부하는지 검증한다.
    /// - 검증 내용: lifecycle invalidPersistedState와 원본 bytes 보존.
    /// - 사전 조건: provider handle만 누락된 running snapshot이 실제 file store에 저장되어 있다.
    /// - 기대 결과: hydration은 partial install 없이 실패하고 같은 snapshot은 재시도에서도 유지된다.
    @Test
    func `invalid running snapshot does not reserve its host`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("runtime-state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalidState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [
                RuntimeStoredSession(
                    externalAgentSessionReference: "host-a",
                    providerInternalSessionReference: nil,
                    runReference: RuntimeRunReference("run-a"),
                    adapterID: RuntimeAdapterID("sdk"),
                    adapterVersion: "1.0.0",
                    capabilitySnapshot: .allSupported,
                    storedContext: RuntimeStoredContext(contextPolicy: reviewRegressionTestsMakeContext()),
                    projection: .running,
                    lastSequence: 0,
                ),
            ],
        )
        try JSONEncoder().encode(invalidState).write(to: fileURL, options: .atomic)
        let adapter = DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
        let plane = RuntimeControlPlane(store: RuntimeFileStateStore(fileURL: fileURL))
        try await plane.register(adapter)
        let launch = makeLaunch(host: "host-a", run: RuntimeRunReference("run-b"), adapterID: "sdk")

        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            _ = try await runPolicyReady(plane, launch)
        }
        #expect(!FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
        await #expect(throws: RuntimeHostError.invalidPersistedState) {
            _ = try await runPolicyReady(plane, launch)
        }
        #expect(await plane.sessions.isEmpty)
        #expect(await plane.hydrated == false)
        #expect(await plane.hydrationTask == nil)
        #expect(await adapter.counts().launch == 0)
    }

    /// ATI-006-project_external_agent_run_events: cancelling consumer task preserves the active run.
    /// caller task 취소가 명시적 provider interruption 없이 durable terminal 상태를 만들지 않는지 검증한다.
    /// - 검증 내용: CancellationError 전파, running projection과 persisted nonterminal 상태, adapter 호출 횟수.
    /// - 사전 조건: launch 뒤 terminal event 없이 지연된 provider event stream이 대기한다.
    /// - 기대 결과: run은 interrupted로 저장되지 않고 restore/resume 가능한 active 상태로 남는다.
    @Test
    func `cancelled run does not persist interruption`() async throws {
        let host: ExternalAgentSessionReference = "host-consumer-cancelled"
        let run = RuntimeRunReference("run-consumer-cancelled")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
        #expect(await adapter.counts().launch == 1)
        #expect(await adapter.counts().stream == 1)
        #expect(await adapter.counts().cancellation == 0)
    }

    /// ATI-006-project_external_agent_run_events: terminal evidence releases a cancelled consumer lease.
    /// 취소된 consumer의 exact-run terminal 증거가 orphan lease를 해제해 host 재사용을 허용하는지 검증한다.
    /// - 검증 내용: CancellationError 전파, terminal event 수용, replacement provider 실행.
    /// - 사전 조건: provider stream 대기 중 caller가 취소되고 이후 같은 run의 host terminal이 도착한다.
    /// - 기대 결과: terminal 저장 뒤 replacement가 activeRunExists 없이 완료된다.
    @Test
    func `terminal evidence releases a cancelled consumer lease`() async throws {
        let host: ExternalAgentSessionReference = "host-cancelled-consumer"
        let run = RuntimeRunReference("run-cancelled-consumer")
        let replacementRun = RuntimeRunReference("run-cancelled-consumer-replacement")
        let replacementCompleted = makeEvent(
            host: host,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "cancelled-consumer-replacement-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[], [replacementCompleted]],
            eventStreamDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await plane.projection(for: host) == .running)
        #expect(try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: run,
            sequence: 1,
        ))?.outcome == .completed)
        let replacement = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")
        try await plane.projectPrelaunch(replacement, as: .policyReady)
        #expect(try await plane.run(replacement).outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    /// ATI-006-project_external_agent_run_events: operation APIs preserve caller cancellation.
    /// provider operation 대기 중 caller 취소가 adapterUnavailable로 정규화되지 않는지 검증한다.
    /// - 검증 내용: approval, queued input, cancellation operation의 CancellationError 전파.
    /// - 사전 조건: active run과 취소 가능한 operation delay를 가진 adapter가 구성되어 있다.
    /// - 기대 결과: 세 operation 모두 caller cancellation을 그대로 전파하고 active run은 유지된다.
    @Test(arguments: [
        OperationCancellationCase.approval,
        .queuedInput,
        .cancellation,
    ])
    func `operation APIs preserve caller cancellation`(operation: OperationCancellationCase) async throws {
        let host = ExternalAgentSessionReference("host-operation-cancellation-\(operation.rawValue)")
        let run = RuntimeRunReference("run-operation-cancellation-\(operation.rawValue)")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .seconds(2),
            operationDelay: .seconds(2),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        await adapter.waitForEventStreamCount(1)
        let operationTask = Task {
            switch operation {
            case .approval:
                try await plane.respondToApproval(
                    hostReference: host,
                    requestID: RuntimeApprovalRequestID("approval"),
                    operationID: RuntimeOperationID("approve"),
                )
            case .queuedInput:
                try await plane.enqueueInput(
                    hostReference: host,
                    operationID: RuntimeOperationID("input"),
                    input: RuntimeSensitiveInput("not persisted"),
                )
            case .cancellation:
                try await plane.requestCancellation(
                    hostReference: host,
                    operationID: RuntimeOperationID("cancel"),
                )
            }
        }
        while await operation.invocationCount(in: adapter) == 0 {
            await Task.yield()
        }

        operationTask.cancel()

        await #expect(throws: CancellationError.self) { try await operationTask.value }
        #expect(await plane.projection(for: host) == .running)
        runTask.cancel()
        await #expect(throws: CancellationError.self) { try await runTask.value }
    }

    /// ATI-006-project_external_agent_run_events: terminal transition does not wait for a delayed operation.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `terminal transition does not wait for delayed operation`() async throws {
        let host: ExternalAgentSessionReference = "host-a"
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
            eventStreamDelay: .milliseconds(50),
            operationDelay: .seconds(1),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)

        let runTask = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)
        let cancellationTask = Task {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        let result = try await runTask.value

        #expect(await plane.projection(for: host) == .completed)
        #expect(result.outcome == .completed)
        #expect(await adapter.counts().cancellation == 1)
        cancellationTask.cancel()
        _ = await cancellationTask.result
    }

    /// ATI-006-project_external_agent_run_events: delayed operation cannot cross its runtime lease.
    /// adapter await 중 terminal 전환이 발생하면 오래된 operation 성공을 현재 run에 귀속하지 않는지 검증한다.
    /// - 검증 내용: operation claim의 lease와 revision 재검증 및 terminal projection 보존.
    /// - 사전 조건: cancellation이 adapter gate에서 대기하는 동안 event stream이 run을 완료한다.
    /// - 기대 결과: cancellation 호출은 stale invalidEvent로 끝나고 완료된 run 상태는 유지된다.
    @Test
    func `delayed operation cannot cross its runtime lease`() async throws {
        let host: ExternalAgentSessionReference = "host-operation-lease"
        let run = RuntimeRunReference("run-operation-lease")
        let operationGate = RuntimeTestGate()
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
            eventStreamGate: streamGate,
            operationGate: operationGate,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)
        let cancellationTask = Task {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        while await adapter.counts().cancellation == 0 {
            await Task.yield()
        }

        await streamGate.open()
        #expect(try await runTask.value.outcome == .completed)
        await operationGate.open()

        await #expect(throws: RuntimeHostError.invalidEvent) { try await cancellationTask.value }
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: delayed operation survives a same-lease nonterminal event.
    /// 같은 run의 progress projection이 성공한 operation acknowledgement를 stale 처리하지 않는지 검증한다.
    /// - 검증 내용: operation await 중 provider progress 수용 뒤 lease와 operation 결과.
    /// - 사전 조건: cancellation이 adapter gate에서 대기하고 동일 lease에서 progress event가 저장된다.
    /// - 기대 결과: cancellation은 성공하고 이후 terminal 전환도 정상 완료된다.
    @Test
    func `delayed operation survives a same-lease nonterminal event`() async throws {
        let host: ExternalAgentSessionReference = "host-operation-nonterminal"
        let run = RuntimeRunReference("run-operation-nonterminal")
        let operationGate = RuntimeTestGate()
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 2,
                idempotencyKey: "completed",
                kind: .completed,
            )]],
            eventStreamGate: streamGate,
            operationGate: operationGate,
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)
        let cancellationTask = Task {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        while await adapter.counts().cancellation == 0 {
            await Task.yield()
        }

        _ = try await plane.accept(
            makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "progress", kind: .progress),
            host: host,
            expectedSource: .provider,
        )
        await operationGate.open()

        try await cancellationTask.value
        await streamGate.open()
        #expect(try await runTask.value.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
    }

    /// ATI-006-project_external_agent_run_events: duplicate and ordering evidence survives persistence.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `duplicate and ordering evidence survives persistence`() async throws {
        let host: ExternalAgentSessionReference = "host-a"
        let run = RuntimeRunReference("run-a")
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[
                makeEvent(host: host, run: run, sequence: 2, idempotencyKey: "gap", kind: .progress),
                makeEvent(host: host, run: run, sequence: 2, idempotencyKey: "gap", kind: .progress),
                makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "stale", kind: .progress),
                makeEvent(host: host, run: run, sequence: 3, idempotencyKey: "done", kind: .completed),
            ]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        _ = try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))

        let evidence = try #require(await store.currentState()?.sessions.first?.eventEvidence)
        #expect(evidence.contains(.sequenceGap(expected: 1, received: 2)))
        #expect(evidence.contains(.ignoredDuplicate(RuntimeIdempotencyKey("gap"))))
        #expect(evidence.contains(.staleSequence(lastAccepted: 2, received: 1)))
    }

    /// ATI-006-project_external_agent_run_events: host terminal outcome wins over conflicting provider result.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host terminal outcome wins over conflicting provider result`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-conflict"
        let run = RuntimeRunReference("run-terminal-conflict")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)

        let hostResult = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))

        #expect(hostResult?.outcome == .interrupted)
        #expect(try await task.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: host terminal outcome wins over a late provider terminal event.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host terminal outcome wins over a late provider terminal event`() async throws {
        let host: ExternalAgentSessionReference = "host-terminal-event-conflict"
        let run = RuntimeRunReference("run-terminal-event-conflict")
        let providerCompleted = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "provider-completed",
            kind: .completed,
        )
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[providerCompleted]],
            eventStreamDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)

        _ = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))

        #expect(try await task.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: duplicate provider frames cannot bypass durable processing budget.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `duplicate provider frames cannot bypass durable processing budget`() async throws {
        let host: ExternalAgentSessionReference = "host-frame-budget"
        let run = RuntimeRunReference("run-frame-budget")
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(
                contextPolicy: makeLaunch(host: host, run: run, adapterID: "sdk").contextPolicy,
            ),
            projection: .running,
            lastSequence: 1,
            acceptedEventCount: 1,
            processedEventCount: RuntimeBoundaryLimits.acceptedEventsPerRun,
            acceptedIdempotencyKeys: [RuntimeIdempotencyKey("same")],
            providerNamespace: "sdk",
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        ))
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(
            hostReference: host,
            expectedContext: makeLaunch(host: host, run: run, adapterID: "sdk").contextPolicy,
        ) == .restored)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.accept(
                makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "same", kind: .progress),
                host: host,
                expectedSource: .provider,
            )
        }
        #expect(await store.saveCount == 1)
    }

    /// ATI-006-project_external_agent_run_events: late finish cannot overwrite persisted host terminal.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `late finish cannot overwrite persisted host terminal`() async throws {
        let host: ExternalAgentSessionReference = "host-late-finish"
        let run = RuntimeRunReference("run-late-finish")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)
        _ = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        ))

        #expect(try await task.value.outcome == .interrupted)
        #expect(await plane.projection(for: host) == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: host ingestion surfaces event disposition projections.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host ingestion surfaces event disposition projections`() async throws {
        let host: ExternalAgentSessionReference = "host-a"
        let run = RuntimeRunReference("run-a")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(150),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        await adapter.waitForEventStreamCount(1)

        _ = try await plane.ingestHostEvent(finalReviewTestsMakeHostEvent(
            host: host,
            run: run,
            sequence: 1,
            key: "one",
        ))
        #expect(await plane.projection(for: host) == .eventProjected)
        _ = try await plane.ingestHostEvent(finalReviewTestsMakeHostEvent(
            host: host,
            run: run,
            sequence: 1,
            key: "one",
        ))
        #expect(await plane.projection(for: host) == .eventProjected)
        _ = try await plane.ingestHostEvent(finalReviewTestsMakeHostEvent(
            host: host,
            run: run,
            sequence: 0,
            key: "stale",
        ))
        #expect(await plane.projection(for: host) == .eventOutOfOrder)
        #expect(try await runTask.value.outcome == .completed)
    }

    /// ATI-006-project_external_agent_run_events: accepted event budget survives hydration.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `accepted event budget survives hydration`() async throws {
        let stored = storageBoundaryTestsMakeStored(
            host: "host-budget",
            run: RuntimeRunReference("run-budget"),
            acceptedEventCount: RuntimeBoundaryLimits.acceptedEventsPerRun,
        )
        let plane =
            RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState([stored])))
        try await plane.register(storageBoundaryTestsMakeAdapter())
        #expect(try await plane.restore(
            hostReference: "host-budget",
            expectedContext: storageBoundaryTestsMakeContext(),
        ) == .restored)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.accept(
                makeEvent(
                    host: "host-budget",
                    run: RuntimeRunReference("run-budget"),
                    sequence: 1,
                    idempotencyKey: "provider-budget",
                    kind: .progress,
                ),
                host: "host-budget",
                expectedSource: .provider,
            )
        }
    }

    /// ATI-006-project_external_agent_run_events: fresh control plane hydrates before host event.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `fresh control plane hydrates before host event`() async throws {
        let stored = storageBoundaryTestsMakeStored(host: "host-hydrate", run: RuntimeRunReference("run-hydrate"))
        let plane =
            RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState([stored])))
        try await plane.register(storageBoundaryTestsMakeAdapter())

        let result = try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: "host-hydrate",
            runReference: RuntimeRunReference("run-hydrate"),
            kind: .interrupted,
        ))

        #expect(result?.outcome == .interrupted)
        #expect(await plane.projection(for: "host-hydrate") == .interrupted)
    }

    /// ATI-006-project_external_agent_run_events: inactive hydrated session rejects nonterminal host events.
    /// 복원 검증을 거치지 않은 persisted session이 host progress로 활성화되지 않는지 검증한다.
    /// - 검증 내용: inactive nonterminal session의 progress event 거부와 projection 보존.
    /// - 사전 조건: running projection이 저장됐지만 control plane restore는 수행되지 않았다.
    /// - 기대 결과: host progress는 invalid event로 거부되고 persisted projection은 유지된다.
    @Test
    func `inactive hydrated session rejects nonterminal host events`() async throws {
        let stored = storageBoundaryTestsMakeStored(
            host: "host-inactive-event",
            run: RuntimeRunReference("run-inactive-event"),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState([
            stored,
        ])))
        try await plane.register(storageBoundaryTestsMakeAdapter())

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.ingestHostEvent(finalBoundaryTestsMakeHostProgress(
                host: stored.externalAgentSessionReference,
                run: stored.runReference,
            ))
        }
        #expect(await plane.projection(for: stored.externalAgentSessionReference) == .running)
    }

    /// ATI-006-project_external_agent_run_events: inactive host terminal gap does not reactivate session.
    /// 순서가 건너뛴 terminal evidence가 restore 경계를 우회해 세션을 활성화하지 않는지 검증한다.
    /// - 검증 내용: terminal gap의 out-of-order 기록과 후속 nonterminal event 거부.
    /// - 사전 조건: inactive running session의 host sequence cursor가 0으로 저장되어 있다.
    /// - 기대 결과: sequence 2 terminal은 terminalize하지 않고 세션도 active로 전환하지 않는다.
    @Test
    func `inactive host terminal gap does not reactivate session`() async throws {
        let stored = storageBoundaryTestsMakeStored(
            host: "host-inactive-terminal-gap",
            run: RuntimeRunReference("run-inactive-terminal-gap"),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: storageBoundaryTestsMakeState([
            stored,
        ])))
        try await plane.register(storageBoundaryTestsMakeAdapter())

        #expect(try await plane.ingestHostEvent(RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-terminal-gap"),
            sequence: 2,
            idempotencyKey: RuntimeIdempotencyKey("host-terminal-gap"),
            timestamp: Date(timeIntervalSince1970: 2),
            externalAgentSessionReference: stored.externalAgentSessionReference,
            runReference: stored.runReference,
            kind: .interrupted,
        )) == nil)
        #expect(await plane.projection(for: stored.externalAgentSessionReference) == .eventOutOfOrder)
        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.ingestHostEvent(finalBoundaryTestsMakeHostProgress(
                host: stored.externalAgentSessionReference,
                run: stored.runReference,
            ))
        }
    }

    private func mutatedExecutionContexts(from context: RuntimeContextPolicy) -> [RuntimeContextPolicy] {
        [
            RuntimeContextPolicy(
                branchReference: context.branchReference,
                authorizationGeneration: context.authorizationGeneration,
                localCorrelation: context.localCorrelation,
                workingDirectory: "/private/other-workspace",
                allowedRoots: context.allowedRoots,
                requestContext: context.requestContext,
            ),
            RuntimeContextPolicy(
                branchReference: context.branchReference,
                authorizationGeneration: context.authorizationGeneration,
                localCorrelation: context.localCorrelation,
                workingDirectory: context.workingDirectory,
                allowedRoots: ["/private/other-root"],
                requestContext: context.requestContext,
            ),
            RuntimeContextPolicy(
                branchReference: context.branchReference,
                authorizationGeneration: context.authorizationGeneration,
                localCorrelation: context.localCorrelation,
                workingDirectory: context.workingDirectory,
                allowedRoots: context.allowedRoots,
                requestContext: "other-request",
            ),
        ]
    }

    private func finalBoundaryTestsMakeAdapter(providerNamespace: String = "sdk") -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(
            id: "sdk",
            providerNamespace: providerNamespace,
            transport: .sdkAsyncStream,
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(50),
        )
    }

    private func finalBoundaryTestsMakeApprovalAdapter() -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(50),
        )
    }

    private func contextCapabilityTestsMakeCapabilities(
        workingDirectory: RuntimeCapabilityStatus = .supported,
        additionalRoots: RuntimeCapabilityStatus = .supported,
    ) -> RuntimeCapabilities {
        RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .supported,
            cancellation: .supported,
            queuedInput: .supported,
            terminalResult: .supported,
            workingDirectory: workingDirectory,
            additionalRoots: additionalRoots,
        )
    }

    private func finalBoundaryTestsMakeState(_ sessions: [RuntimeStoredSession]) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: sessions)
    }

    private func finalBoundaryTestsMakeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
            workingDirectory: "/private/workspace",
            allowedRoots: ["/private/workspace"],
            requestContext: "sensitive-request",
        )
    }

    private func finalBoundaryTestsMakeStored(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        acceptedEventCount: Int = 0,
        providerNamespace: String = "sdk",
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .terminalOnly,
            storedContext: RuntimeStoredContext(contextPolicy: finalBoundaryTestsMakeContext()),
            projection: .running,
            lastSequence: 0,
            acceptedEventCount: acceptedEventCount,
            acceptedIdempotencyKeys: [],
            providerNamespace: providerNamespace,
        )
    }

    private func finalBoundaryTestsMakeHostProgress(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-progress"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-progress"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .progress,
        )
    }

    private func finalBoundaryTestsMakeHostTerminal(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-interrupted"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("host-interrupted"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .interrupted,
        )
    }

    private func reviewerBlockerTestsMakeCanonicalContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
            workingDirectory: "/tmp/workspace",
            allowedRoots: ["/tmp/workspace"],
            requestContext: "content-tab",
        )
    }

    private func reviewerBlockerTestsMakeRunningSession(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        context: RuntimeContextPolicy,
        capabilities: RuntimeCapabilities = .allSupported,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: capabilities,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
        )
    }

    private func reviewerBlockerTestsMakeHostTerminal(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        sequence: UInt64,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-terminal-\(sequence)"),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey("terminal-\(sequence)"),
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .completed,
        )
    }

    private func reviewRegressionTestsMakeRunningState() -> RuntimeStoredState {
        reviewRegressionTestsMakeState(projection: .running)
    }

    private func reviewRegressionTestsMakeResumeCapabilities(
        _ status: RuntimeCapabilityStatus,
    ) -> RuntimeCapabilities {
        RuntimeCapabilities(
            discovery: .supported,
            eventStream: .supported,
            approval: .supported,
            cancellation: .supported,
            queuedInput: .supported,
            terminalResult: .supported,
            timeout: .supported,
            sameIdentityResume: status,
            reconstruction: .supported,
            explicitArtifact: .supported,
            workingDirectory: .supported,
            additionalRoots: .supported,
            authStatusProbe: .supported,
        )
    }

    private func reviewRegressionTestsExpectUnavailableResume(
        _ status: RuntimeCapabilityStatus,
        plane: RuntimeControlPlane,
        stored: RuntimeStoredSession,
    ) async throws {
        switch status {
        case .unknown:
            await #expect(throws: RuntimeHostError.capabilityUnknown(.sameIdentityResume)) {
                try await plane.restore(
                    hostReference: stored.externalAgentSessionReference,
                    expectedContext: reviewRegressionTestsMakeContext(),
                )
            }
        case .unsupported:
            await #expect(throws: RuntimeHostError.capabilityUnsupported(.sameIdentityResume)) {
                try await plane.restore(
                    hostReference: stored.externalAgentSessionReference,
                    expectedContext: reviewRegressionTestsMakeContext(),
                )
            }
        case .supported:
            throw RuntimeHostError.invalidEvent
        }
    }

    private func reviewRegressionTestsMakeState(projection: RuntimeProjection) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [RuntimeStoredSession(
            externalAgentSessionReference: "host-a",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-a"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: reviewRegressionTestsMakeContext()),
            projection: projection,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
        )])
    }

    private func reviewRegressionTestsMakeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
        )
    }

    private func sourceIsolationTestsMakeHostProgress(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        sequence: UInt64,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-progress-\(sequence)"),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey("host-progress-\(sequence)"),
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .progress,
        )
    }

    private func boundedModelTestsMakeCanonicalContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
            workingDirectory: "/tmp/workspace",
            allowedRoots: ["/tmp/workspace"],
            requestContext: "content-tab",
        )
    }

    private func boundedModelTestsMakeRunningSession(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        context: RuntimeContextPolicy,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: context),
            projection: .running,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
        )
    }

    private func boundedModelTestsMakeHostProgress(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        sequence: UInt64,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-progress-\(sequence)"),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey("progress-\(sequence)"),
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .progress,
        )
    }

    private func persistenceContractTestsMakeStoredSession() -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: ExternalAgentSessionReference("host-a"),
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-a"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            )),
            projection: .running,
            lastSequence: 2,
            acceptedIdempotencyKeys: [RuntimeIdempotencyKey("event-a")],
        )
    }

    private func finalContractTestsMakeStoredState(projection: RuntimeProjection) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [RuntimeStoredSession(
            externalAgentSessionReference: "host-a",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-a"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            )),
            projection: projection,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
        )])
    }

    private func finalReviewTestsMakeAdapter() -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]])
    }

    private func finalReviewTestsMakeHostEvent(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        sequence: UInt64,
        key: String,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-\(sequence)"),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey(key),
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            externalAgentSessionReference: host,
            runReference: run,
            kind: .progress,
        )
    }

    private func finalReviewTestsMakeStoredSession(providerBranch: RuntimeProviderBranch) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: "host-a",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-a"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: finalReviewTestsMakeContext()),
            projection: .running,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
            providerBranch: providerBranch,
        )
    }

    private func makeSecondReceiptConflictFixture(
        finalState: SecondReceiptConflictFinalState,
    ) -> SecondReceiptConflictFixture {
        let host = ExternalAgentSessionReference("host-second-receipt-conflict")
        let originalRun = RuntimeRunReference("run-second-receipt-conflict-original")
        let replacementRun = RuntimeRunReference("run-second-receipt-conflict-replacement")
        let cleanupReplacementRun = RuntimeRunReference("run-second-receipt-conflict-cleanup")
        let finalReplacementRun = RuntimeRunReference("run-second-receipt-conflict-final")
        let originalTerminal = makeSecondReceiptConflictTerminal(host: host, run: originalRun, provider: nil)
        let replacementTerminal = makeSecondReceiptConflictTerminal(
            host: host,
            run: replacementRun,
            provider: ProviderInternalSessionReference("replacement-opaque"),
        )
        let cleanupReplacementTerminal = makeSecondReceiptConflictTerminal(
            host: host,
            run: cleanupReplacementRun,
            provider: ProviderInternalSessionReference("cleanup-opaque"),
        )
        let finalReplacementTerminal = makeSecondReceiptConflictTerminal(
            host: host,
            run: finalReplacementRun,
            provider: ProviderInternalSessionReference("final-opaque"),
        )
        let expectedFinalTerminal = finalState == .sameRunTerminal ? originalTerminal : finalReplacementTerminal
        let loadStates = finalState == .sameRunTerminal
            ? [3: makeState([originalTerminal]), 4: makeState([originalTerminal])]
            : [:]
        let store = DeterministicHostMutationRuntimeStateStore(
            loadStates: loadStates,
            conflictingUpdateStates: [
                3: makeState([originalTerminal]),
                4: makeState([replacementTerminal]),
                5: makeState([cleanupReplacementTerminal]),
                6: makeState([finalReplacementTerminal]),
            ],
        )
        return SecondReceiptConflictFixture(
            host: host,
            originalRun: originalRun,
            expectedFinalRun: expectedFinalTerminal.runReference,
            expectedFinalProvider: expectedFinalTerminal.providerInternalSessionReference,
            expectedFinalTerminal: expectedFinalTerminal,
            store: store,
            adapter: DeterministicRuntimeAdapter(id: "sdk", transport: .sdkAsyncStream, eventsByLaunch: [[]]),
            plane: RuntimeControlPlane(store: store),
        )
    }

    private func makeSecondReceiptConflictTerminal(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        provider: ProviderInternalSessionReference?,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: provider,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: finalReviewTestsMakeContext()),
            projection: .completed,
            providerLaunchAttempted: true,
        )
    }

    private struct SecondReceiptConflictFixture {
        let host: ExternalAgentSessionReference
        let originalRun: RuntimeRunReference
        let expectedFinalRun: RuntimeRunReference
        let expectedFinalProvider: ProviderInternalSessionReference?
        let expectedFinalTerminal: RuntimeStoredSession
        let store: DeterministicHostMutationRuntimeStateStore
        let adapter: DeterministicRuntimeAdapter
        let plane: RuntimeControlPlane
    }

    enum SecondReceiptConflictFinalState: CaseIterable {
        case replacement
        case sameRunTerminal
    }

    private func reviewerBlockerTestsWaitForResumeClaimBoundary(
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

    private func reviewerBlockerTestsWaitForPendingPersistenceMutations(
        _ count: Int,
        host: ExternalAgentSessionReference,
        on plane: RuntimeControlPlane,
    ) async throws {
        for _ in 0 ..< 10000 {
            if await plane.pendingPersistenceMutations[host, default: 0] >= count { return }
            await Task.yield()
        }
        throw RuntimeHostError.invalidEvent
    }

    private func reviewerBlockerTestsWaitForPersistenceWaiters(
        _ count: Int,
        on plane: RuntimeControlPlane,
    ) async throws {
        for _ in 0 ..< 10000 {
            if await plane.persistenceMutationWaiters.count >= count { return }
            await Task.yield()
        }
        throw RuntimeHostError.invalidEvent
    }

    private func reviewerBlockerTestsMakeResumeClaimRace() async throws -> ResumeClaimRaceFixture {
        let host = ExternalAgentSessionReference("host-resume-claim")
        let run = RuntimeRunReference("run-resume-claim")
        let context = finalReviewTestsMakeContext()
        let saveGate = RuntimeTestGate()
        let streamGate = RuntimeTestGate()
        let stored = reviewerBlockerTestsMakeRunningSession(host: host, run: run, context: context)
        let store = InMemoryRuntimeStateStore(
            state: RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [stored]),
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
        return ResumeClaimRaceFixture(
            host: host,
            saveGate: saveGate,
            streamGate: streamGate,
            store: store,
            adapter: adapter,
            plane: plane,
        )
    }

    private struct ResumeClaimRaceFixture {
        let host: ExternalAgentSessionReference
        let saveGate: RuntimeTestGate
        let streamGate: RuntimeTestGate
        let store: InMemoryRuntimeStateStore
        let adapter: DeterministicRuntimeAdapter
        let plane: RuntimeControlPlane
    }

    private func makeHydrationGenerationOwnershipFixture() -> HydrationGenerationOwnershipFixture {
        let firstLoadGate = RuntimeTestGate()
        let secondLoadGate = RuntimeTestGate()
        let invalidStored = RuntimeStoredSession(
            externalAgentSessionReference: "host-stale-waiter",
            providerInternalSessionReference: nil,
            runReference: RuntimeRunReference("run-stale-waiter"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: finalBoundaryTestsMakeContext()),
            projection: .running,
            providerNamespace: "provider-a",
        )
        let validStored = storageBoundaryTestsMakeStored(
            host: "host-fresh-generation",
            run: RuntimeRunReference("run-fresh-generation"),
        )
        let store = InMemoryRuntimeStateStore(
            state: finalBoundaryTestsMakeState([invalidStored]),
            loadGates: [1: firstLoadGate, 2: secondLoadGate],
        )
        let plane = RuntimeControlPlane(store: store)
        let first = Task(priority: .high) { try await plane.hydrateIfNeeded() }
        let stale = Task(priority: .background) { try await plane.hydrateIfNeeded() }
        return HydrationGenerationOwnershipFixture(
            firstLoadGate: firstLoadGate,
            secondLoadGate: secondLoadGate,
            validStored: validStored,
            store: store,
            plane: plane,
            first: first,
            stale: stale,
        )
    }

    private struct HydrationGenerationOwnershipFixture {
        let firstLoadGate: RuntimeTestGate
        let secondLoadGate: RuntimeTestGate
        let validStored: RuntimeStoredSession
        let store: InMemoryRuntimeStateStore
        let plane: RuntimeControlPlane
        let first: Task<Void, Error>
        let stale: Task<Void, Error>
    }

    private struct StaleLifecycleHydrationFixture {
        let firstLoadGate: RuntimeTestGate
        let secondLoadGate: RuntimeTestGate
        let validStored: RuntimeStoredSession
        let store: InMemoryRuntimeStateStore
        let plane: RuntimeControlPlane
        let first: Task<Void, Error>
        let second: Task<Void, Error>
    }

    private func makeStaleLifecycleHydrationFixture() async -> StaleLifecycleHydrationFixture {
        let firstLoadGate = RuntimeTestGate()
        let secondLoadGate = RuntimeTestGate()
        let invalidStored = RuntimeStoredSession(
            externalAgentSessionReference: "host-invalid-generation",
            providerInternalSessionReference: nil,
            runReference: RuntimeRunReference("run-invalid-generation"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: finalBoundaryTestsMakeContext()),
            projection: .running,
            providerNamespace: "provider-a",
        )
        let validStored = storageBoundaryTestsMakeStored(
            host: "host-valid-generation",
            run: RuntimeRunReference("run-valid-generation"),
        )
        let store = InMemoryRuntimeStateStore(
            state: finalBoundaryTestsMakeState([invalidStored]),
            loadGates: [1: firstLoadGate, 2: secondLoadGate],
        )
        let plane = RuntimeControlPlane(store: store)
        let first = Task(priority: .high) { try await plane.hydrateIfNeeded() }
        await store.waitForLoadCount(1)
        return StaleLifecycleHydrationFixture(
            firstLoadGate: firstLoadGate,
            secondLoadGate: secondLoadGate,
            validStored: validStored,
            store: store,
            plane: plane,
            first: first,
            second: Task(priority: .background) { try await plane.hydrateIfNeeded() },
        )
    }

    private struct ResumptionCleanupFixture {
        let context: RuntimeContextPolicy
        let host: ExternalAgentSessionReference
        let replacement: RuntimeStoredSession
        let replacementState: RuntimeStoredState
        let cleanupGate: RuntimeTestGate
        let store: DeterministicHostMutationRuntimeStateStore
        let adapter: DeterministicRuntimeAdapter
        let plane: RuntimeControlPlane
    }

    private func makeResumptionCleanupFixture(
        failure: PersistenceBoundaryFailure,
    ) async throws -> ResumptionCleanupFixture {
        let context = finalReviewTestsMakeContext()
        let host = ExternalAgentSessionReference("host-resume-cleanup-\(failure.rawValue)")
        let replacement = makeResumptionReplacement(failure: failure, host: host, context: context)
        let stored = makeResumptionStored(failure: failure, host: host, context: context)
        let replacementState = RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [replacement],
        )
        let cleanupGate = RuntimeTestGate()
        let store = DeterministicHostMutationRuntimeStateStore(
            state: RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: [stored],
            ),
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
        return ResumptionCleanupFixture(
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

    private func makeResumptionReplacement(
        failure: PersistenceBoundaryFailure,
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

    private func makeResumptionStored(
        failure: PersistenceBoundaryFailure,
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

    private func finalReviewTestsMakeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
        )
    }

    private func storageBoundaryTestsMakeAdapter() -> DeterministicRuntimeAdapter {
        DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: storageBoundaryTestsMakeCapabilities(),
            eventsByLaunch: [[]],
        )
    }

    private func storageBoundaryTestsMakeCapabilities() -> RuntimeCapabilities {
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

    private func storageBoundaryTestsMakeState(_ sessions: [RuntimeStoredSession]) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: sessions)
    }

    private func storageBoundaryTestsMakeContext() -> RuntimeContextPolicy {
        RuntimeContextPolicy(
            branchReference: "feat/voy-696",
            authorizationGeneration: 1,
            localCorrelation: "local-a",
        )
    }

    private func storageBoundaryTestsMakeStored(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        acceptedEventCount: Int = 0,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-1"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: storageBoundaryTestsMakeCapabilities(),
            storedContext: RuntimeStoredContext(contextPolicy: storageBoundaryTestsMakeContext()),
            projection: .running,
            lastSequence: 0,
            acceptedEventCount: acceptedEventCount,
        )
    }
}

extension RuntimeControlPlane {
    func testSupersedeHydration(with task: Task<RuntimeStoredState?, Error>) {
        hydrationGeneration &+= 1
        hydrationTask = task
    }
}

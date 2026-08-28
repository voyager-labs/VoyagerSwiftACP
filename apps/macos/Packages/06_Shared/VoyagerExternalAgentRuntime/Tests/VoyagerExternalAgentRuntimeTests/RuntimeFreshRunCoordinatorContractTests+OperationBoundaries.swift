import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

enum OperationBoundaryCase: String, CaseIterable {
    case respondToApproval
    case enqueueInput
    case requestCancellation
}

/// gate 뒤 operation task의 완료를 bounded 폴링으로 관찰하기 위한 lock box.
private final class OperationBoundaryOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?
    private var recorded = false

    func recordSucceeded() {
        lock.lock()
        defer { lock.unlock() }
        recorded = true
    }

    func recordFailure(_ failure: any Error) {
        lock.lock()
        defer { lock.unlock() }
        error = failure
        recorded = true
    }

    var hasOutcome: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func caughtError() -> (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-747-operation_boundaries_cancel: cancelled operation never reaches provider.
    /// 진입 전에 이미 취소된 control plane operation이 provider adapter side effect를 전달하지 않는 경계를 고정한다.
    /// - 검증 내용: CancellationError 재노출, adapter approval/input/cancellation 호출 0회, consuming lease와 running projection
    /// 유지.
    /// - 사전 조건: event stream gate로 유지되는 running consuming 세션과 start gate 뒤에서 취소된 operation task가 있다.
    /// - 기대 결과: 각 operation은 CancellationError로 종료되고 provider 도달 횟수는 0회며 세션 상태는 변하지 않는다.
    @Test(arguments: OperationBoundaryCase.allCases)
    func `cancelled operation never reaches provider`(boundary: OperationBoundaryCase) async throws {
        let host = ExternalAgentSessionReference("host-operation-boundary-cancel-\(boundary.rawValue)")
        let run = RuntimeRunReference("run-operation-boundary-cancel-\(boundary.rawValue)")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
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

        // 테스트 측 start gate: plane 호출이 시작되기 전에 취소가 확정되도록 보장한다.
        let startGate = RuntimeTestGate()
        let outcome = OperationBoundaryOutcomeBox()
        let opTask = Task {
            await startGate.wait()
            do {
                switch boundary {
                case .respondToApproval:
                    try await plane.respondToApproval(
                        hostReference: host,
                        requestID: RuntimeApprovalRequestID("approval-operation-boundary"),
                        operationID: RuntimeOperationID("operation-boundary"),
                    )
                case .enqueueInput:
                    try await plane.enqueueInput(
                        hostReference: host,
                        operationID: RuntimeOperationID("operation-boundary"),
                        input: RuntimeSensitiveInput("not persisted"),
                    )
                case .requestCancellation:
                    try await plane.requestCancellation(
                        hostReference: host,
                        operationID: RuntimeOperationID("operation-boundary"),
                    )
                }
                outcome.recordSucceeded()
            } catch {
                outcome.recordFailure(error)
            }
        }
        opTask.cancel()
        await startGate.open()

        var finished = false
        for _ in 0 ..< 600 {
            if outcome.hasOutcome {
                finished = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        let caughtError = outcome.caughtError()
        #expect(finished, "operation task must finish within the bounded window")
        #expect(
            caughtError is CancellationError,
            "cancelled operation must surface CancellationError, got \(String(describing: caughtError))",
        )

        let counts = await adapter.counts()
        switch boundary {
        case .respondToApproval:
            #expect(counts.approval == 0, "cancelled approval must not reach the provider, count=\(counts.approval)")
        case .enqueueInput:
            #expect(counts.input == 0, "cancelled input must not reach the provider, count=\(counts.input)")
        case .requestCancellation:
            #expect(
                counts.cancellation == 0,
                "cancelled cancellation must not reach the provider, count=\(counts.cancellation)",
            )
        }

        // Optional(RuntimeLease) 비교에서 .none 리터럴은 Optional.none으로 묶이므로 정규화된 케이스로 검사한다.
        let heldLease = await plane.sessions[host]?.lease
        var leaseHeld = false
        if case .consuming = heldLease { leaseHeld = true }
        #expect(leaseHeld, "session lease must remain consuming, held=\(String(describing: heldLease))")
        #expect(await plane.projection(for: host) == .running)

        await streamGate.open()
        _ = try? await runTask.value
    }

    /// VOY-747-operation_boundaries_max_sequence: max sequence event is rejected at admission.
    /// UInt64.max sequence 이벤트가 admission 경계에서 거부되어 persisted cursor 오버플로 오염을 막는지 고정한다.
    /// - 검증 내용: malformedAdapterResponse 거부, lastSequence 0 유지, 후속 sequence 1 progress 이벤트의 무오류 수용과 cursor 1 진행.
    /// - 사전 조건: event stream gate로 유지되는 running consuming 세션이 있다.
    /// - 기대 결과: max sequence 이벤트는 저장 없이 거부되고 후속 정상 이벤트는 cursor integrity를 유지한 채 수용된다.
    @Test
    func `max sequence event is rejected at admission`() async throws {
        let host: ExternalAgentSessionReference = "host-max-sequence-admission"
        let run = RuntimeRunReference("run-max-sequence-admission")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
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

        let poisonedEvent = makeEvent(
            host: host,
            run: run,
            sequence: UInt64.max,
            idempotencyKey: "max-sequence-poison",
            kind: .progress,
        )
        var admissionError: Error?
        do {
            _ = try await plane.accept(poisonedEvent, host: host, expectedSource: .provider)
        } catch {
            admissionError = error
        }
        let thrownHostError = admissionError.flatMap { $0 as? RuntimeHostError }
        #expect(
            thrownHostError == .malformedAdapterResponse,
            "max sequence event must be rejected at admission, got \(String(describing: admissionError))",
        )

        // 거부 없이 수용되면 후속 cursor 연산이 오버플로 트랩에 빠지므로 거부가 확인된 뒤에만 무결성을 검증한다.
        guard thrownHostError != nil else {
            await streamGate.open()
            _ = try? await runTask.value
            return
        }

        let persistedAfterRejection = try #require(await store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host }))
        #expect(persistedAfterRejection.lastSequence == 0)

        let followUpEvent = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "normal-followup",
            kind: .progress,
        )
        var followUpError: Error?
        do {
            _ = try await plane.accept(followUpEvent, host: host, expectedSource: .provider)
        } catch {
            followUpError = error
        }
        #expect(
            followUpError == nil,
            "normal follow-up event must be accepted after rejection, got \(String(describing: followUpError))",
        )

        let persistedAfterFollowUp = try #require(await store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host }))
        #expect(persistedAfterFollowUp.lastSequence == 1)

        await streamGate.open()
        _ = try? await runTask.value
    }

    // MARK: - ATI-006-project_external_agent_run_events

    /// ATI-006-project_external_agent_run_events: detached consuming owner cannot issue provider operations.
    /// receipt 저장 후 caller 취소로 탈부착된 consuming 소유자가 provider 승인·입력·취소 연산을 시작할 수 없는지 검증한다.
    /// - 검증 내용: 세 operation 모두 소유자 입증 단계에서 invalidEvent로 거부되고 adapter 호출 카운터와 run/projection/lease/durable
    ///   상태가 불변이다.
    /// - 사전 조건: receipt 저장(save 3) 이후 caller cancel로 detachedConsuming 소유자가 남아 있고 provider stream은 gate로 막혀 있다.
    /// - 기대 결과: 각 operation은 RuntimeHostError.invalidEvent를 던지고 카운터는 0회이며 상태 스냅샷과 동일하게 유지된다.
    @Test
    func `detached consuming owner cannot issue provider operations`() async throws {
        let host: ExternalAgentSessionReference = "host-detached-consuming-operations"
        let run = RuntimeRunReference("run-detached-consuming-operations")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        let runTask = Task { try await plane.run(request) }
        // 결정적 탈부착 시점: receipt 저장(save 3)까지 대기한 뒤 caller cancel을 선형화한다.
        await store.waitForSaveCount(3)
        runTask.cancel()
        await #expect(throws: CancellationError.self) { try await runTask.value }
        let detached = try #require(await plane.sessions[host])
        guard case .detachedConsuming = detached.lease else {
            Issue.record("receipt 이후 caller cancel은 detachedConsuming 소유자를 남겨야 한다: \(detached.lease)")
            await streamGate.open()
            return
        }
        #expect(detached.stored.projection == .running)
        let baseline = try await detachedOwnerBaseline(host: host, store: store, session: detached)

        try await assertDetachedOwnerRejectsOperations(
            host: host,
            adapter: adapter,
            plane: plane,
            store: store,
            baseline: baseline,
        )
        await streamGate.open()
    }

    /// ATI-006-project_external_agent_run_events: detached launching owner cannot issue provider operations.
    /// launch gate 대기 중 caller 취소와 취소 저장 실패(save 3)로 남은 detachedLaunching 소유자의 provider 연산 차단을 검증한다.
    /// - 검증 내용: 세 operation 모두 소유자 입증 단계에서 invalidEvent로 거부되며 승인 연산은 provider 참조 조회 이전에 거부된다.
    /// - 사전 조건: pre-receipt 취소 저장 실패로 detachedLaunching 소유자가 남아 있고 projection은 launching이다.
    /// - 기대 결과: 각 operation은 RuntimeHostError.invalidEvent를 던지고 카운터는 0회이며 상태 스냅샷과 동일하게 유지된다.
    @Test
    func `detached launching owner cannot issue provider operations`() async throws {
        let host: ExternalAgentSessionReference = "host-detached-launching-operations"
        let run = RuntimeRunReference("run-detached-launching-operations")
        let launchGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByLaunch: [[]],
            launchGate: launchGate,
        )
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [3])
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        let runTask = Task { try await plane.run(request) }
        await adapter.waitForLaunchCount(1)
        runTask.cancel()
        await launchGate.open()
        await #expect(throws: CancellationError.self) { try await runTask.value }
        let detached = try #require(await plane.sessions[host])
        guard case .detachedLaunching = detached.lease else {
            Issue.record("취소 저장 실패 뒤 launch owner는 detachedLaunching이어야 한다: \(detached.lease)")
            return
        }
        #expect(detached.stored.projection == .launching)
        let baseline = try await detachedOwnerBaseline(host: host, store: store, session: detached)

        try await assertDetachedOwnerRejectsOperations(
            host: host,
            adapter: adapter,
            plane: plane,
            store: store,
            baseline: baseline,
        )
    }

    /// ATI-006-project_external_agent_run_events: live consuming owner completes provider operations exactly once.
    /// 라이브 consuming 소유자의 승인·입력·취소 연산이 정확히 한 번씩 성공하는 긍정 제어를 검증한다.
    /// - 검증 내용: 세 operation의 성공, approval correlation 필드, projection/lease/durable 상태 불변.
    /// - 사전 조건: receipt 저장 후 running consuming 소유자가 있고 provider stream은 gate로 막혀 있다.
    /// - 기대 결과: 각 operation은 한 번씩 adapter에 도달하고 상태는 연산 전 스냅샷과 동일하게 유지된다.
    @Test
    func `live consuming owner completes provider operations exactly once`() async throws {
        let fixture = try await makeLiveOperationFixture()
        let live = try #require(await fixture.plane.sessions[fixture.host])
        guard case .consuming = live.lease else {
            Issue.record("receipt 저장 뒤 소유자는 consuming이어야 한다: \(live.lease)")
            await fixture.streamGate.open()
            _ = try? await fixture.runTask.value
            return
        }
        let baselinePersisted = try #require(await fixture.store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == fixture.host }))
        let saveCountBeforeOperations = await fixture.store.saveCount
        try await assertLiveProviderOperations(fixture)
        #expect(await fixture.plane.projection(for: fixture.host) == .running)
        #expect(await fixture.plane.sessions[fixture.host] == live)
        #expect(await fixture.store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == fixture.host }) == baselinePersisted)
        #expect(await fixture.store.saveCount == saveCountBeforeOperations)
        await fixture.streamGate.open()
        #expect(try await fixture.runTask.value.outcome == .completed)
    }

    private struct LiveOperationFixture {
        let host: ExternalAgentSessionReference
        let run: RuntimeRunReference
        let streamGate: RuntimeTestGate
        let adapter: DeterministicRuntimeAdapter
        let store: InMemoryRuntimeStateStore
        let plane: RuntimeControlPlane
        let runTask: Task<RuntimeResult, Error>
    }

    private func makeLiveOperationFixture() async throws -> LiveOperationFixture {
        let host: ExternalAgentSessionReference = "host-live-consuming-operations"
        let run = RuntimeRunReference("run-live-consuming-operations")
        let streamGate = RuntimeTestGate()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
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
            eventStreamGate: streamGate,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)
        let runTask = Task { try await plane.run(request) }
        try await waitForProjection(.running, host: host, on: plane)
        return LiveOperationFixture(
            host: host,
            run: run,
            streamGate: streamGate,
            adapter: adapter,
            store: store,
            plane: plane,
            runTask: runTask,
        )
    }

    private func assertLiveProviderOperations(_ fixture: LiveOperationFixture) async throws {
        try await fixture.plane.respondToApproval(
            hostReference: fixture.host,
            requestID: RuntimeApprovalRequestID("approval-live"),
            operationID: RuntimeOperationID("operation-live"),
        )
        try await fixture.plane.enqueueInput(
            hostReference: fixture.host,
            operationID: RuntimeOperationID("input-live"),
            input: RuntimeSensitiveInput("not persisted"),
        )
        try await fixture.plane.requestCancellation(
            hostReference: fixture.host,
            operationID: RuntimeOperationID("cancel-live"),
        )
        let counts = await fixture.adapter.counts()
        #expect(counts.approval == 1)
        #expect(counts.input == 1)
        #expect(counts.cancellation == 1)
        let approval = try #require(await fixture.adapter.receivedApprovalRequests().first)
        #expect(approval.externalAgentSessionReference == fixture.host)
        #expect(approval.providerInternalSessionReference == ProviderInternalSessionReference("opaque-1"))
        #expect(approval.requestID == RuntimeApprovalRequestID("approval-live"))
        #expect(approval.operationID == RuntimeOperationID("operation-live"))
        #expect(approval.runReference == fixture.run)
        #expect(approval.authorizationGeneration == 1)
    }

    /// 탈부착 소유자 단언을 위한 연산 전 상태 스냅샷.
    private struct DetachedOwnerBaseline {
        let session: RuntimeControlPlane.Session
        let persisted: RuntimeStoredSession
        let saveCount: Int
    }

    /// 연산 전 durable store와 persistence 카운터 스냅샷을 수집한다.
    private func detachedOwnerBaseline(
        host: ExternalAgentSessionReference,
        store: InMemoryRuntimeStateStore,
        session: RuntimeControlPlane.Session,
    ) async throws -> DetachedOwnerBaseline {
        try await DetachedOwnerBaseline(
            session: session,
            persisted: #require(store.currentState()?.sessions
                .first(where: { $0.externalAgentSessionReference == host })),
            saveCount: store.saveCount,
        )
    }

    /// 탈부착 소유자 공통 단언: 세 provider operation의 invalidEvent 거부와 무효과를 검증한다.
    private func assertDetachedOwnerRejectsOperations(
        host: ExternalAgentSessionReference,
        adapter: DeterministicRuntimeAdapter,
        plane: RuntimeControlPlane,
        store: InMemoryRuntimeStateStore,
        baseline: DetachedOwnerBaseline,
    ) async throws {
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.respondToApproval(
                hostReference: host,
                requestID: RuntimeApprovalRequestID("approval-detached"),
                operationID: RuntimeOperationID("operation-detached"),
            )
        }
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.enqueueInput(
                hostReference: host,
                operationID: RuntimeOperationID("input-detached"),
                input: RuntimeSensitiveInput("not persisted"),
            )
        }
        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.requestCancellation(
                hostReference: host,
                operationID: RuntimeOperationID("cancel-detached"),
            )
        }

        let counts = await adapter.counts()
        #expect(counts.approval == 0)
        #expect(counts.input == 0)
        #expect(counts.cancellation == 0)
        #expect(await plane.sessions[host] == baseline.session)
        #expect(await store.currentState()?.sessions
            .first(where: { $0.externalAgentSessionReference == host }) == baseline.persisted)
        #expect(await store.saveCount == baseline.saveCount)
    }
}

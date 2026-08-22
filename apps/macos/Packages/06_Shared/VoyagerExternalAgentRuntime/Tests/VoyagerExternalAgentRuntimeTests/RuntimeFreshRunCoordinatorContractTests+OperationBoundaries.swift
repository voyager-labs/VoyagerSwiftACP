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
}

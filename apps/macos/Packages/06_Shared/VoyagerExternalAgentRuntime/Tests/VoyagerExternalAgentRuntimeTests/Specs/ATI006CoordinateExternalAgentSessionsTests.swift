import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("ATI-006 Coordinate External Agent Sessions")
struct ATI006CoordinateExternalAgentSessionsTests {
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
            eventsByLaunch: [[makeEvent(
                host: host,
                run: run,
                sequence: 1,
                idempotencyKey: "done",
                kind: .completed,
            )]],
            eventStreamDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        try await Task.sleep(for: .milliseconds(20))

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

    // MARK: - ATI-006-coordinate_external_agent_launch

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
        try await Task.sleep(for: .milliseconds(20))

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

    /// ATI-006-coordinate_external_agent_launch: failed prelaunch can retry the same run reference.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `failed prelaunch can retry the same run reference`() async throws {
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
        #expect(try await runPolicyReady(plane, request).outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    /// ATI-006-coordinate_external_agent_launch: failed launch cleanup can recover after persistence failure.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: launch 실패 정리 저장이 실패해도 새 host가 같은 run을 다시 policy-ready로 만들 수 있다.
    /// - 사전 조건: provider launch가 한 번 실패하고 launch-failed 저장만 실패한다.
    /// - 기대 결과: persisted pre-provider launching 상태가 provider 실행으로 오인되지 않고 같은 run 재시도가 완료된다.
    @Test
    func `failed launch cleanup can recover after persistence failure`() async throws {
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

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await firstPlane.run(request)
        }

        let recoveredPlane = RuntimeControlPlane(store: store)
        try await recoveredPlane.register(adapter)
        try await recoveredPlane.projectPrelaunch(request, as: .policyReady)

        #expect(try await recoveredPlane.run(request).outcome == .completed)
        #expect(await adapter.counts().launch == 2)
    }

    /// ATI-006-coordinate_external_agent_launch: bind persistence failure cannot relaunch a started provider run.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: provider receipt 이후 bind 저장 실패를 pre-provider launch 실패와 구분한다.
    /// - 사전 조건: provider launch는 성공하고 bind snapshot 저장만 실패한다.
    /// - 기대 결과: run은 interrupted로 보존되고 동일 run 재시도가 provider를 다시 시작하지 않는다.
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
        #expect(await recoveredPlane.projection(for: host) == .interrupted)
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
        try await Task.sleep(for: .milliseconds(20))
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
        try await store.save(RuntimeStoredState(
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
            contextPolicy: context,
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
            contextPolicy: context,
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
            failingSaveNumbers: [1, 2],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        #expect(try await plane.restore(hostReference: host, expectedContext: context) == .restored)

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            try await plane.resumeRestoredRun(hostReference: host)
        }
        let retried = try await plane.resumeRestoredRun(hostReference: host)

        #expect(retried.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        #expect(await adapter.counts().stream == 2)
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
        try await store.save(RuntimeStoredState(
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

        for context in mutatedExecutionContexts(from: stored.contextPolicy) {
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
        try await store.save(RuntimeStoredState(
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

    /// ATI-006-coordinate_external_agent_run_continuity: unknown same identity resume capability fails closed.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `unknown same identity resume capability fails closed`() async throws {
        let stored = RuntimeStoredSession(
            externalAgentSessionReference: "host-resume-unknown",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-resume-unknown"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .terminalOnly,
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
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
            capabilities: .terminalOnly,
            eventsByLaunch: [[]],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)

        await #expect(throws: RuntimeHostError.capabilityUnknown(.sameIdentityResume)) {
            try await plane.restore(
                hostReference: stored.externalAgentSessionReference,
                expectedContext: stored.contextPolicy,
            )
        }
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
        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
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
        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
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
        try await Task.sleep(for: .milliseconds(20))

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
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            eventStreamDelay: .milliseconds(500),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        try await Task.sleep(for: .milliseconds(20))

        let result = try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(
            host: host,
            run: run,
            sequence: 2,
        ))

        #expect(result == nil)
        #expect(await plane.projection(for: host) == .eventOutOfOrder)
        #expect(try await task.value.outcome == .completed)
    }

    /// ATI-006-project_external_agent_run_events: host terminal during launch cannot be overwritten by binding.
    /// 외부 에이전트 세션 조정 계약의 이 시나리오를 검증한다.
    /// - 검증 내용: 실행 가능한 상태, 효과, persistence 또는 event projection 경계.
    /// - 사전 조건: 결정적 adapter와 isolated runtime state store가 구성되어 있다.
    /// - 기대 결과: 해당 interaction의 관찰 가능한 결과와 오류 경계가 유지된다.
    @Test
    func `host terminal during launch cannot be overwritten by binding`() async throws {
        let host: ExternalAgentSessionReference = "host-launch"
        let run = RuntimeRunReference("run-launch")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchDelay: .milliseconds(100),
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let task = Task { try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk")) }
        try await Task.sleep(for: .milliseconds(20))

        _ = try await plane.ingestHostEvent(reviewerBlockerTestsMakeHostTerminal(host: host, run: run, sequence: 1))

        await #expect(throws: RuntimeHostError.invalidEvent) { try await task.value }
        #expect(await plane.projection(for: host) == .completed)
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
        try await Task.sleep(for: .milliseconds(20))
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
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore())
        try await plane.register(adapter)
        let runTask = Task {
            try await runPolicyReady(plane, makeLaunch(host: host, run: run, adapterID: "sdk"))
        }
        try await waitForProjection(.running, host: host, on: plane)
        await plane.beginTerminalTransition(host)
        await plane.beginTerminalTransition(host)
        await plane.endTerminalTransition(host)

        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        #expect(await adapter.counts().cancellation == 0)

        await plane.endTerminalTransition(host)
        runTask.cancel()
        _ = await runTask.result
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
        try await Task.sleep(for: .milliseconds(20))
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
        try await Task.sleep(for: .milliseconds(20))
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
            contextPolicy: boundedModelTestsMakeCanonicalContext(),
            projection: .running,
            lastSequence: 0,
            eventEvidence: [.ignoredDuplicate(oversized)],
        )
        let plane = RuntimeControlPlane(store: InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [stored],
        )))

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
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
    /// provider handle이 없는 running snapshot을 격리한 뒤 같은 host를 새 실행에 사용할 수 있는지 검증한다.
    /// - 검증 내용: current-schema invariant 위반의 quarantine과 다음 hydration의 host reservation 해제.
    /// - 사전 조건: provider handle만 누락된 running snapshot이 실제 file store에 저장되어 있다.
    /// - 기대 결과: 최초 load는 persistence failure이고 재시도한 새 실행은 완료된다.
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
                    contextPolicy: reviewRegressionTestsMakeContext(),
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

        await #expect(throws: RuntimeHostError.persistenceFailure) {
            _ = try await runPolicyReady(plane, launch)
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))
        #expect(try await runPolicyReady(plane, launch).outcome == .completed)
        #expect(await adapter.counts().launch == 1)
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
        try await Task.sleep(for: .milliseconds(20))
        let cancellationTask = Task {
            try await plane.requestCancellation(hostReference: host, operationID: RuntimeOperationID("cancel"))
        }
        try await Task.sleep(for: .milliseconds(70))

        #expect(await plane.projection(for: host) == .completed)
        #expect(try await runTask.value.outcome == .completed)
        #expect(await adapter.counts().cancellation == 1)
        cancellationTask.cancel()
        _ = await cancellationTask.result
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
            contextPolicy: makeLaunch(host: host, run: run, adapterID: "sdk").contextPolicy,
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
            expectedContext: stored.contextPolicy,
        ) == .restored)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.accept(
                makeEvent(host: host, run: run, sequence: 1, idempotencyKey: "same", kind: .progress),
                host: host,
                expectedSource: .provider,
            )
        }
        #expect(await store.saveCount == 0)
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

        await plane.finish(
            RuntimeResult(runReference: run, outcome: .completed, artifactReferences: []),
            host: host,
        )

        #expect(await plane.projection(for: host) == .interrupted)
        #expect(try await task.value.outcome == .interrupted)
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
        try await Task.sleep(for: .milliseconds(20))

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
            contextPolicy: finalBoundaryTestsMakeContext(),
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
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            contextPolicy: context,
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

    private func reviewRegressionTestsMakeState(projection: RuntimeProjection) -> RuntimeStoredState {
        RuntimeStoredState(schemaVersion: RuntimeStoredState.currentSchemaVersion, sessions: [RuntimeStoredSession(
            externalAgentSessionReference: "host-a",
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-provider-handle"),
            runReference: RuntimeRunReference("run-a"),
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            contextPolicy: reviewRegressionTestsMakeContext(),
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
            contextPolicy: context,
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
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
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
            contextPolicy: RuntimeContextPolicy(
                branchReference: "feat/voy-696",
                authorizationGeneration: 1,
                localCorrelation: "local-a",
            ),
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
            contextPolicy: finalReviewTestsMakeContext(),
            projection: .running,
            lastSequence: 0,
            acceptedIdempotencyKeys: [],
            providerBranch: providerBranch,
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
            contextPolicy: storageBoundaryTestsMakeContext(),
            projection: .running,
            lastSequence: 0,
            acceptedEventCount: acceptedEventCount,
        )
    }
}

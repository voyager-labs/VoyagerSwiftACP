import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-747-fresh_uncooperative_provider: fresh caller cancellation escapes before the uncooperative provider gate
    /// opens.
    /// provider event stream이 취소에 반응하지 않아도 fresh run의 caller 취소가 gate 개방 전에 탈출하는지 고정한다.
    /// - 검증 내용: gate 개방 전 CancellationError 반환, detached consuming lease, running projection과 launch 1회.
    /// - 사전 조건: receipt 이후 provider event stream 호출이 취소 비협조 invocation gate에서 대기한다.
    /// - 기대 결과: 취소된 caller는 gate를 열기 전에 CancellationError를 받고 소유권은 detached consuming이 된다.
    @Test
    func `fresh caller cancellation escapes before uncooperative provider gate opens`() async throws {
        let fixture = makeUncooperativeProviderFreshRunFixture()
        try await fixture.plane.register(fixture.adapter)
        try await fixture.plane.projectPrelaunch(fixture.request, as: .policyReady)

        let runTask = Task { try await fixture.plane.run(fixture.request) }
        let recorder = ResumeProbeRecorder()
        let monitor = Task {
            do {
                try await recorder.record(.result(runTask.value))
            } catch is CancellationError {
                await recorder.record(.cancellation)
            } catch {
                await recorder.record(.failure(String(describing: error)))
            }
        }
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.invocationGate.waitUntilWaiting()

        runTask.cancel()

        var escaped = false
        for _ in 0 ..< 600 {
            if await recorder.waitForValue(maxYields: 1) {
                escaped = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard escaped, await recorder.value == .cancellation else {
            await Issue
                .record(
                    "caller 취소는 uncooperative provider gate 개방 전에 CancellationError로 탈출해야 한다: escaped=\(escaped), value=\(String(describing: recorder.value))",
                )
            await finishUncooperativeFreshRunProbe(fixture, monitor)
            return
        }

        // canonical detachment: 소유권은 detached consuming이고 projection은 running으로 유지된다.
        let session = try #require(await fixture.plane.sessions[fixture.host])
        guard case .detachedConsuming = session.lease else {
            Issue.record("탈출 뒤 소유권은 detached consuming이어야 한다: \(session.lease)")
            await finishUncooperativeFreshRunProbe(fixture, monitor)
            return
        }
        #expect(session.stored.projection == .running)
        #expect(await fixture.adapter.counts().launch == 1)

        await finishUncooperativeFreshRunProbe(fixture, monitor)
    }

    /// VOY-747-fresh_uncooperative_provider: background provider converges after caller escape and fences replacement.
    /// caller 탈출 뒤에도 배경 provider가 terminal 수렴을 완주하고 교체를 보호하는지 고정한다.
    /// - 검증 내용: gate 폐쇄 중 교체 prelaunch activeRunExists 거부, 개방 뒤 durable/local terminal 수렴과 lease 해제, 정확한 호출 횟수와 교체 성공.
    /// - 사전 조건: 첫 event stream이 gate에서 대기하는 동안 caller가 탈출한 detached consuming 상태다.
    /// - 기대 결과: old provider는 배경에서 정확히 한 번 수렴하고 lease 해제 뒤 교체 prelaunch와 실행이 성공한다.
    @Test
    func `fresh background provider converges after escape and fences replacement`() async throws {
        let fixture = makeUncooperativeProviderFreshRunFixture()
        try await fixture.plane.register(fixture.adapter)
        try await fixture.plane.projectPrelaunch(fixture.request, as: .policyReady)

        let runTask = Task { try await fixture.plane.run(fixture.request) }
        let recorder = ResumeProbeRecorder()
        let monitor = Task {
            do {
                try await recorder.record(.result(runTask.value))
            } catch is CancellationError {
                await recorder.record(.cancellation)
            } catch {
                await recorder.record(.failure(String(describing: error)))
            }
        }
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.invocationGate.waitUntilWaiting()

        runTask.cancel()

        var escaped = false
        for _ in 0 ..< 600 {
            if await recorder.waitForValue(maxYields: 1) {
                escaped = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard escaped, await recorder.value == .cancellation else {
            await Issue
                .record(
                    "caller 취소는 uncooperative provider gate 개방 전에 CancellationError로 탈출해야 한다: escaped=\(escaped), value=\(String(describing: recorder.value))",
                )
            await finishUncooperativeFreshRunProbe(fixture, monitor)
            return
        }

        // gate가 닫혀 있는 동안 같은 host 교체 prelaunch는 거부된다.
        await #expect(throws: RuntimeHostError.activeRunExists) {
            try await fixture.plane.projectPrelaunch(fixture.replacementRequest, as: .policyReady)
        }

        // gate 개방: old provider가 배경에서 수렴을 완주한다.
        await fixture.invocationGate.open()
        var converged = false
        for _ in 0 ..< 600 {
            if let stored = await fixture.store.currentState()?.sessions.first(where: {
                $0.externalAgentSessionReference == fixture.host
            }), stored.projection == .completed {
                converged = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(converged, "배경 provider의 terminal은 durable하게 수렴해야 한다")
        var released = false
        for _ in 0 ..< 600 {
            if await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none {
                released = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(released, "terminal 수렴 뒤 detached 소유권은 해제되어야 한다")

        // old run의 provider 호출은 정확히 한 번씩이다.
        var counts = await fixture.adapter.counts()
        #expect(counts.launch == 1)
        #expect(counts.stream == 1)

        // lease 해제 뒤 교체 prelaunch와 실행이 성공한다.
        try await fixture.plane.projectPrelaunch(fixture.replacementRequest, as: .policyReady)
        #expect(try await fixture.plane.run(fixture.replacementRequest).outcome == .completed)
        counts = await fixture.adapter.counts()
        #expect(counts.launch == 2)
        #expect(counts.stream == 2)

        _ = await monitor.value
    }

    /// VOY-747-fresh_uncooperative_provider: background provider failure is observed after escape.
    /// caller 탈출 뒤 provider가 실패해도 배경 드레인이 실패를 관찰해 소유권을 정리하는지 고정한다.
    /// - 검증 내용: gate 개방 뒤 durable interrupted 수렴, lease 해제, 교체 prelaunch와 실행 성공.
    /// - 사전 조건: 첫 event stream이 gate에서 대기하는 동안 caller가 탈출한 detached consuming 상태다.
    /// - 기대 결과: 개방 뒤 stream 생성 실패가 interrupt 전이로 반영되고 교체 실행이 성공한다.
    @Test
    func `fresh background provider failure is observed after escape`() async throws {
        let host: ExternalAgentSessionReference = "uncooperative-fresh-failure-host"
        let run = RuntimeRunReference("uncooperative-fresh-failure-run")
        let replacementRun = RuntimeRunReference("uncooperative-fresh-failure-replacement")
        let invocationGate = RuntimeTestGate()
        let failure = RuntimeAdapterFailure(kind: .transportLoss, diagnosticCode: RuntimeDiagnosticCode("gate_loss"))
        let oldCompleted = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "uncooperative-fresh-failure-completed",
            kind: .completed,
        )
        let replacementCompleted = makeEvent(
            host: host,
            run: replacementRun,
            sequence: 1,
            idempotencyKey: "uncooperative-fresh-failure-replacement-completed",
            kind: .completed,
        )
        let store = InMemoryRuntimeStateStore()
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: uncooperativeStreamCapabilities,
            eventsByEventStream: [[oldCompleted], [replacementCompleted]],
            eventStreamInvocationGate: invocationGate,
            eventStreamRuntimeFailuresByLaunch: [1: failure],
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        let (recorder, monitor) = monitorFreshRun(runTask)
        await adapter.waitForEventStreamCount(1)
        await invocationGate.waitUntilWaiting()

        runTask.cancel()
        var escaped = false
        for _ in 0 ..< 600 {
            if await recorder.waitForValue(maxYields: 1) {
                escaped = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        guard escaped, await recorder.value == .cancellation else {
            await Issue.record("caller 취소는 provider 실패 노출 전에 탈출해야 한다: \(String(describing: recorder.value))")
            await invocationGate.open()
            _ = await monitor.value
            return
        }

        // gate 개방: provider stream 생성이 실패하고 배경 드레인이 이를 관찰해 interrupt로 수렴한다.
        await invocationGate.open()
        var interrupted = false
        for _ in 0 ..< 600 {
            if let stored = await store.currentState()?.sessions.first(where: {
                $0.externalAgentSessionReference == host
            }), stored.projection == .interrupted {
                interrupted = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(interrupted, "배경 provider 실패는 durable interrupted로 관찰되어야 한다")
        var released = false
        for _ in 0 ..< 600 {
            if await plane.sessions[host]?.lease == RuntimeControlPlane.RuntimeLease.none {
                released = true
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(released, "실패 수렴 뒤 detached 소유권은 해제되어야 한다")

        // 정리 뒤 같은 host 교체 prelaunch와 실행이 성공한다.
        let replacementRequest = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")
        try await plane.projectPrelaunch(replacementRequest, as: .policyReady)
        #expect(try await plane.run(replacementRequest).outcome == .completed)

        _ = await monitor.value
    }

    /// VOY-438-p1_a: abandoned provider persistence-conflict cleanup remains observable.
    /// caller 탈출 뒤 provider terminal 수렴과 detached owner 복구가 persistence conflict로 실패해도 실패 근거가 유실되지 않는지 고정한다.
    /// - 검증 내용: caller CancellationError, background failed convergence, exact persistence cleanup evidence, no
    /// relaunch/retry.
    /// - 사전 조건: provider의 completed event 저장과 abandoned detached owner 복구 저장이 연속으로 persistence conflict를 반환한다.
    /// - 기대 결과: caller 취소는 보존되고 detached consuming 이후 배경 실패가 같은 run의 persistence evidence로 관찰되며 provider는 재호출되지 않는다.
    @Test
    func `abandoned provider persistence conflict records cleanup failure`() async throws {
        let host: ExternalAgentSessionReference = "uncooperative-abandoned-persistence-conflict-host"
        let run = RuntimeRunReference("uncooperative-abandoned-persistence-conflict-run")
        let invocationGate = RuntimeTestGate()
        let completed = makeEvent(
            host: host,
            run: run,
            sequence: 1,
            idempotencyKey: "uncooperative-abandoned-persistence-conflict-completed",
            kind: .completed,
        )
        let store = InMemoryRuntimeStateStore(conflictingSaveNumbers: [5, 6])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByEventStream: [[completed]],
            eventStreamInvocationGate: invocationGate,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        let (recorder, monitor) = monitorFreshRun(runTask)
        await adapter.waitForEventStreamCount(1)
        await invocationGate.waitUntilWaiting()

        runTask.cancel()
        #expect(await recorder.waitForValue(), "caller cancellation must escape before the provider gate opens")
        #expect(await recorder.value == .cancellation, "caller cancellation must remain CancellationError")

        let detached = try #require(await plane.sessions[host])
        guard case .detachedConsuming = detached.lease else {
            Issue.record("caller escape must establish detached consuming ownership: \(detached.lease)")
            await invocationGate.open()
            _ = await monitor.value
            return
        }

        await invocationGate.open()
        await store.waitForSaveCount(6)
        let recordedFailure = await waitForCleanupFailureEvidence(plane: plane, host: host)

        #expect(recordedFailure, "abandoned failed convergence must retain cleanup failure evidence")
        #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
            runReference: run,
            kind: .persistence,
        ))
        #expect(await store.applyCount == 6, "provider failure and detached recovery must each reach the conflict seam")
        let leaseAfterRecovery = await plane.sessions[host]?.lease
        #expect(
            isDetachedConsuming(leaseAfterRecovery),
            "failed recovery must preserve the detached owner for later convergence: \(String(describing: leaseAfterRecovery))",
        )
        let counts = await adapter.counts()
        #expect(counts.launch == 1)
        #expect(counts.stream == 1)
        #expect(counts.terminalResult == 0)
        _ = await monitor.value
    }

    private func waitForCleanupFailureEvidence(
        plane: RuntimeControlPlane,
        host: ExternalAgentSessionReference,
    ) async -> Bool {
        for _ in 0 ..< 600 {
            if await plane.cleanupFailureEvidence(for: host) != nil { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    /// VOY-747-fresh_uncooperative_provider: background terminal persistence failure remains observable and
    /// recoverable.
    /// caller 탈출 뒤 terminal result 저장이 실패해도 정리 실패 근거와 cross-plane 회복 경계가 유지되는지 고정한다.
    /// - 검증 내용: save 5 실패 뒤 persistence evidence, running/detached 소유권, persisted terminal 동기화와 교체 승인.
    /// - 사전 조건: 빈 provider stream이 invocation gate에서 대기하고 terminal result 저장만 실패한다.
    /// - 기대 결과: 실패는 삼켜지지 않고 관찰되며 다른 plane의 terminal 저장 뒤 교체 prelaunch가 성공한다.
    @Test
    func `fresh background terminal persistence failure remains observable and recoverable`() async throws {
        let host: ExternalAgentSessionReference = "uncooperative-terminal-persistence-host"
        let run = RuntimeRunReference("uncooperative-terminal-persistence-run")
        let replacementRun = RuntimeRunReference("uncooperative-terminal-persistence-replacement")
        let invocationGate = RuntimeTestGate()
        let store = InMemoryRuntimeStateStore(failingSaveNumbers: [5])
        let terminal = RuntimeResult(runReference: run, outcome: .completed, artifactReferences: [])
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            capabilities: .allSupported,
            eventsByEventStream: [[]],
            eventStreamInvocationGate: invocationGate,
            terminalResultOverride: terminal,
        )
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let replacementRequest = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        let runTask = Task { try await plane.run(request) }
        let recorder = ResumeProbeRecorder()
        let monitor = Task {
            do {
                try await recorder.record(.result(runTask.value))
            } catch is CancellationError {
                await recorder.record(.cancellation)
            } catch {
                await recorder.record(.failure(String(describing: error)))
            }
        }
        await adapter.waitForEventStreamCount(1)
        await invocationGate.waitUntilWaiting()

        runTask.cancel()
        guard await recorder.waitForValue(), await recorder.value == .cancellation else {
            Issue.record("caller 취소는 terminal persistence 시도 전에 CancellationError로 탈출해야 한다")
            await invocationGate.open()
            _ = await monitor.value
            return
        }
        let detached = try #require(await plane.sessions[host])
        #expect(isDetachedConsuming(detached.lease))
        #expect(detached.stored.projection == .running)

        try await assertBackgroundTerminalPersistenceFailure(
            plane: plane,
            store: store,
            invocationGate: invocationGate,
            host: host,
            run: run,
        )
        try await persistCrossPlaneTerminalAndAdmitReplacement(
            plane: plane,
            store: store,
            request: replacementRequest,
            originalRun: run,
        )

        _ = await monitor.value
    }

    private func assertBackgroundTerminalPersistenceFailure(
        plane: RuntimeControlPlane,
        store: InMemoryRuntimeStateStore,
        invocationGate: RuntimeTestGate,
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) async throws {
        await invocationGate.open()
        await store.waitForSaveCount(5)
        var recordedFailure = false
        for _ in 0 ..< 600 {
            if await plane.cleanupFailureEvidence(for: host) != nil {
                recordedFailure = true
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(recordedFailure, "배경 terminal persistence 실패는 cleanup evidence로 관찰되어야 한다")
        #expect(await plane.cleanupFailureEvidence(for: host) == RuntimeCleanupFailureEvidence(
            runReference: run,
            kind: .persistence,
        ))
        #expect(await plane.projection(for: host) == .running)
        #expect(await store.currentState()?.sessions.first?.projection == .running)
        #expect(await isDetachedConsuming(plane.sessions[host]?.lease))
    }

    private func monitorFreshRun(
        _ runTask: Task<RuntimeResult, any Error>,
    ) -> (ResumeProbeRecorder, Task<Void, Never>) {
        let recorder = ResumeProbeRecorder()
        let monitor = Task {
            do {
                try await recorder.record(.result(runTask.value))
            } catch is CancellationError {
                await recorder.record(.cancellation)
            } catch {
                await recorder.record(.failure(String(describing: error)))
            }
        }
        return (recorder, monitor)
    }

    private func isDetachedConsuming(
        _ lease: RuntimeControlPlane.RuntimeLease?,
    ) -> Bool {
        if case .detachedConsuming = lease { return true }
        return false
    }

    private func persistCrossPlaneTerminalAndAdmitReplacement(
        plane: RuntimeControlPlane,
        store: InMemoryRuntimeStateStore,
        request: RuntimeLaunchRequest,
        originalRun: RuntimeRunReference,
    ) async throws {
        let terminalPlane = RuntimeControlPlane(store: store)
        let terminalEvent = RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("uncooperative-terminal-persistence-host-event"),
            sequence: 1,
            idempotencyKey: RuntimeIdempotencyKey("uncooperative-terminal-persistence-host-event"),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: request.externalAgentSessionReference,
            runReference: originalRun,
            kind: .completed,
        )
        #expect(try await terminalPlane.ingestHostEvent(terminalEvent)?.outcome == .completed)
        try await plane.projectPrelaunch(request, as: .policyReady)
        #expect(await plane.projection(for: request.externalAgentSessionReference) == .policyReady)
        #expect(await store.currentState()?.sessions.first?.runReference == request.runReference)
    }

    /// probe 종료 시 gate와 대기 작업을 반드시 정리해 테스트 뒤 유출이 없도록 한다.
    private func finishUncooperativeFreshRunProbe(
        _ fixture: UncooperativeProviderFreshRunFixture,
        _ monitor: Task<Void, Never>,
    ) async {
        await fixture.invocationGate.open()
        _ = await monitor.value
    }

    /// VOY-747-fresh_uncooperative_provider: voy696 mailbox pressure regression.
    /// caller 취소와 provider deliver가 우편함에서 경합할 때 단말 복사본이 유실되지 않는지 압력으로 고정한다.
    /// - 검증 내용: 400개 사례 각각에서 cancel 직후 gate를 열어 deliver와 cancelWaiter 재개 경합을 유도하고,
    ///   durable completed 수렴, detached 소유권 해제(lease none), launch/stream 정확히 1회,
    ///   수렴 이후 교체 prelaunch 승인을 집계해 유실 사례 0건을 요구한다.
    /// - 사전 조건: 각 사례는 독립된 plane/adapter와 비협조 invocation gate를 가지며,
    ///   provider event stream이 gate에서 대기 중인 상태로 caller를 취소한다.
    /// - 기대 결과: 경합 순서(deliver 선승/cancelWaiter 선승)와 무관하게 모든 사례가 배경 수렴으로 완주된다.
    @Test
    func `fresh provider race mailbox hands terminal to abandoned convergence under pressure`() async {
        let caseCount = 400
        let batchSize = 16
        var observations: [MailboxPressureCaseObservation] = []
        var nextIndex = 0
        while nextIndex < caseCount {
            let batchEnd = min(nextIndex + batchSize, caseCount)
            await withTaskGroup(of: MailboxPressureCaseObservation.self) { group in
                for caseIndex in nextIndex ..< batchEnd {
                    group.addTask {
                        await runFreshMailboxPressureCase(caseIndex)
                    }
                }
                for await observation in group {
                    observations.append(observation)
                }
            }
            nextIndex = batchEnd
        }

        let staleCases = observations.filter { !$0.converged }
        #expect(
            staleCases.isEmpty,
            "우편함 경합에서 단말이 유실된 사례가 없어야 한다: 유실 \(staleCases.count)건, 예시 \(staleCases.prefix(3))",
        )
        let unreleasedCases = observations.filter { $0.converged && !$0.leaseReleased }
        #expect(
            unreleasedCases.isEmpty,
            "수렴한 사례의 detached 소유권은 해제되어야 한다: 미해제 \(unreleasedCases.count)건, 예시 \(unreleasedCases.prefix(3))",
        )
        let doubleRunCases = observations.filter {
            $0.converged && ($0.launchCount != 1 || $0.streamCount != 1)
        }
        #expect(
            doubleRunCases.isEmpty,
            "provider launch/stream은 사례당 정확히 한 번이어야 한다: 위반 \(doubleRunCases.count)건, 예시 \(doubleRunCases.prefix(3))",
        )
        let unadmittedCases = observations.filter { $0.converged && !$0.replacementAdmitted }
        #expect(
            unadmittedCases.isEmpty,
            "수렴 이후 같은 host 교체 prelaunch는 승인되어야 한다: 미승인 \(unadmittedCases.count)건, 예시 \(unadmittedCases.prefix(3))",
        )
    }
}

/// 우편함 압력 회귀의 사례별 관찰 결과다. 집계 단계에서 문자열로 요약해 진단한다.
private struct MailboxPressureCaseObservation: Equatable {
    let index: Int
    let converged: Bool
    let leaseReleased: Bool
    let launchCount: Int?
    let streamCount: Int?
    let replacementAdmitted: Bool
    let finalProjection: String?
    let finalLease: String?
    let callerOutcome: String?
}

/// voy696 압력 사례 1건이다. cancel 직후 gate를 열어 deliver/cancelWaiter 경합을 최대화한다.
private func runFreshMailboxPressureCase(_ index: Int) async -> MailboxPressureCaseObservation {
    let host = ExternalAgentSessionReference("voy696-mailbox-pressure-host-\(index)")
    let run = RuntimeRunReference("voy696-mailbox-pressure-run-\(index)")
    let replacementRun = RuntimeRunReference("voy696-mailbox-pressure-replacement-\(index)")
    let invocationGate = RuntimeTestGate()
    let oldCompleted = makeEvent(
        host: host,
        run: run,
        sequence: 1,
        idempotencyKey: "voy696-mailbox-pressure-completed-\(index)",
        kind: .completed,
    )
    let replacementCompleted = makeEvent(
        host: host,
        run: replacementRun,
        sequence: 1,
        idempotencyKey: "voy696-mailbox-pressure-replacement-completed-\(index)",
        kind: .completed,
    )
    let store = InMemoryRuntimeStateStore()
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: uncooperativeStreamCapabilities,
        eventsByEventStream: [[oldCompleted], [replacementCompleted]],
        eventStreamInvocationGate: invocationGate,
    )
    let plane = RuntimeControlPlane(store: store)
    let request = makeLaunch(host: host, run: run, adapterID: "sdk")
    let replacementRequest = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")

    do {
        try await plane.register(adapter)
        try await plane.projectPrelaunch(request, as: .policyReady)
    } catch {
        return MailboxPressureCaseObservation(
            index: index,
            converged: false,
            leaseReleased: false,
            launchCount: nil,
            streamCount: nil,
            replacementAdmitted: false,
            finalProjection: "setupFailed(\(String(describing: error)))",
            finalLease: nil,
            callerOutcome: nil,
        )
    }

    let runTask = Task { try await plane.run(request) }
    let recorder = ResumeProbeRecorder()
    let monitor = Task {
        do {
            try await recorder.record(.result(runTask.value))
        } catch is CancellationError {
            await recorder.record(.cancellation)
        } catch {
            await recorder.record(.failure(String(describing: error)))
        }
    }
    await adapter.waitForEventStreamCount(1)
    await invocationGate.waitUntilWaiting()

    // cancel과 gate 개방의 선후와 간격을 사례별로 샘플링해 deliver/cancelWaiter 경합 창 전체를 압력으로 담는다.
    // 짝수 사례는 cancel 선승(T_cancel 먼저 도착), 홀수 사례는 개방 후 미세 지연 뒤 cancel로
    // provider deliver 체인에 선두를 준다. 지연 단계는 인덱스로 순환해 기계 편차를 흡수한다.
    if index.isMultiple(of: 2) {
        runTask.cancel()
        await invocationGate.open()
    } else {
        await invocationGate.open()
        let pressureDelays: [UInt64] = [50000, 150_000, 400_000, 900_000]
        try? await Task.sleep(nanoseconds: pressureDelays[(index / 2) % pressureDelays.count])
        await Task.yield()
        runTask.cancel()
    }

    // 1단계: 단말 투영 대기. 2단계: 투영 완료 뒤 소유권 해제는 별도 경계에서 늦게 반영되므로
    // 해제를 별도 예산으로 기다린다. 두 단계가 모두 예산 안에 끝나야 수렴으로 인정한다.
    var converged = false
    var leaseReleased = false
    var finalProjection: String?
    var finalLease: String?
    for _ in 0 ..< 1000 {
        if let session = await plane.sessions[host] {
            finalProjection = String(describing: session.stored.projection)
            finalLease = String(describing: session.lease)
            if session.stored.projection == .completed {
                converged = true
                break
            }
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    if converged {
        for _ in 0 ..< 1000 {
            if let session = await plane.sessions[host] {
                finalProjection = String(describing: session.stored.projection)
                finalLease = String(describing: session.lease)
                if session.lease == RuntimeControlPlane.RuntimeLease.none {
                    leaseReleased = true
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    var launchCount: Int?
    var streamCount: Int?
    var replacementAdmitted = false
    if converged {
        let counts = await adapter.counts()
        launchCount = counts.launch
        streamCount = counts.stream
        do {
            try await plane.projectPrelaunch(replacementRequest, as: .policyReady)
            replacementAdmitted = true
        } catch {
            replacementAdmitted = false
        }
    }

    _ = await recorder.waitForValue(maxYields: 1)
    let callerOutcome = await recorder.value
    _ = await monitor.value

    return MailboxPressureCaseObservation(
        index: index,
        converged: converged,
        leaseReleased: leaseReleased,
        launchCount: launchCount,
        streamCount: streamCount,
        replacementAdmitted: replacementAdmitted,
        finalProjection: finalProjection,
        finalLease: finalLease,
        callerOutcome: callerOutcome.map(String.init(describing:)),
    )
}

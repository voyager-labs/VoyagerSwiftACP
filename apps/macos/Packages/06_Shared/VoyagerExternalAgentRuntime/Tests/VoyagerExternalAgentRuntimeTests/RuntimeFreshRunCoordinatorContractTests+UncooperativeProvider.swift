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

    /// probe 종료 시 gate와 대기 작업을 반드시 정리해 테스트 뒤 유출이 없도록 한다.
    private func finishUncooperativeFreshRunProbe(
        _ fixture: UncooperativeProviderFreshRunFixture,
        _ monitor: Task<Void, Never>,
    ) async {
        await fixture.invocationGate.open()
        _ = await monitor.value
    }
}

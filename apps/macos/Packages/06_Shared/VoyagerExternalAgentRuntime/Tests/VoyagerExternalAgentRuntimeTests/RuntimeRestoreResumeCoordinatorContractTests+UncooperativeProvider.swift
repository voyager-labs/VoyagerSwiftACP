import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-uncooperative_provider_terminal

    /// VOY-747-uncooperative_provider_terminal: same-run host terminal wins while the provider stream gate remains
    /// closed.
    /// provider event stream이 취소에 반응하지 않아도 host terminal과 heartbeat 승자가 public resume을 즉시 완료하는지 검증한다.
    /// - 검증 내용: gate 해제 전 completed 반환, claim/lease 정리, provider 호출 횟수와 late event 무시.
    /// - 사전 조건: event stream은 noncancellable gate에서 대기하고 다른 plane이 같은 run의 completed terminal을 저장한다.
    /// - 기대 결과: gate를 열기 전에 resume이 completed를 반환하고, gate 해제 후 old provider event가 terminal/claim을 바꾸지 않는다.
    @Test
    func `same run host terminal returns before uncooperative provider gate opens`() async throws {
        let fixture = makeUncooperativeProviderHostTerminalFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)

        let recorder = ResumeProbeRecorder()
        let resume = startResume(on: fixture.plane, host: fixture.host, recorder: recorder)
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.streamGate.waitUntilWaiting()
        await fixture.clock.waitUntilSleeping()

        let hostPlane = RuntimeControlPlane(
            store: fixture.store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: fixture.clock.runtimeClock,
        )
        #expect(try await hostPlane.ingestHostEvent(fixture.hostTerminal)?.outcome == .completed)
        await fixture.clock.releaseSleepers()

        #expect(await recorder.waitForValue())
        #expect(await recorder.value == .result(RuntimeResult(
            runReference: fixture.run,
            outcome: .completed,
            artifactReferences: [],
        )))
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim == nil)
        let countsBeforeGate = await fixture.adapter.counts()
        #expect(countsBeforeGate.stream == 1)
        #expect(countsBeforeGate.terminalResult == 0)

        await fixture.streamGate.open()
        _ = await resume.value
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(await fixture.plane.projection(for: fixture.host) == .completed)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.store.currentState()?.sessions.first?.projection == .completed)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await fixture.plane.acceptedEventCount(for: fixture.host) == 0)
        let countsAfterGate = await fixture.adapter.counts()
        #expect(countsAfterGate.stream == 1)
        #expect(countsAfterGate.terminalResult == 0)
    }

    // MARK: - VOY-747-uncooperative_provider_cancellation

    /// VOY-747-uncooperative_provider_cancellation: caller cancellation returns before the provider gate opens and
    /// permits a replacement attempt.
    /// caller가 복원 resume을 취소해도 old provider child를 기다리지 않고 동일 run의 다음 attempt를 보호하는지 검증한다.
    /// - 검증 내용: bounded cancellation 반환, 기존 retry claim/lease 계약, replacement event와 old late event의 attempt fence.
    /// - 사전 조건: 첫 event stream은 gate에서 대기하고 두 번째 stream은 completed event를 반환하며 두 stream 모두 같은 gate를 공유한다.
    /// - 기대 결과: 첫 resume은 gate 해제 전에 CancellationError로 끝나고, 두 번째 attempt만 completed terminal을 저장한다.
    @Test
    func `caller cancellation returns before uncooperative provider gate and fences replacement attempt`() async throws {
        let fixture = makeUncooperativeProviderCancellationFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)

        let firstRecorder = ResumeProbeRecorder()
        let firstResume = startResume(on: fixture.plane, host: fixture.host, recorder: firstRecorder)
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.streamGate.waitUntilWaiting()
        await fixture.clock.waitUntilSleeping()

        firstResume.cancel()
        let returnedBeforeGate = await firstRecorder.waitForValue()
        #expect(returnedBeforeGate)
        guard returnedBeforeGate else {
            await fixture.streamGate.open()
            _ = await firstResume.value
            return
        }
        #expect(await firstRecorder.value == .cancellation)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.restored(1))
        let retryClaim = try #require(await fixture.store.currentState()?.sessions.first?.restorationClaim)
        let ownerToken = await fixture.plane.restorationOwnerToken
        #expect(retryClaim.ownerToken == ownerToken)

        let secondRecorder = ResumeProbeRecorder()
        let secondResume = startResume(on: fixture.plane, host: fixture.host, recorder: secondRecorder)
        await fixture.adapter.waitForEventStreamCount(2)
        await fixture.streamGate.open()

        #expect(await secondRecorder.waitForValue())
        #expect(await secondRecorder.value == .result(RuntimeResult(
            runReference: fixture.run,
            outcome: .completed,
            artifactReferences: [],
        )))
        _ = await secondResume.value
        _ = await firstResume.value
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(await fixture.plane.projection(for: fixture.host) == .completed)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.store.currentState()?.sessions.first?.projection == .completed)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await fixture.plane.acceptedEventCount(for: fixture.host) == 1)
        let counts = await fixture.adapter.counts()
        #expect(counts.stream == 2)
        #expect(counts.terminalResult == 0)
    }

    // MARK: - VOY-747-provider_terminal_cas_loss

    /// VOY-747-provider_terminal_cas_loss: provider terminal CAS loss adopts the same-run host terminal without losing
    /// the resuming owner.
    /// provider terminal event가 host terminal과 CAS 충돌해도 heartbeat보다 먼저 durable host terminal로 수렴하는지 검증한다.
    /// - 검증 내용: provider apply #3 대기, host terminal apply #4, read-repair 결과와 restored owner finalization.
    /// - 사전 조건: active restored attempt가 provider failed event를 처리하고 heartbeat는 deterministic sleeper에서 대기한다.
    /// - 기대 결과: completed host terminal이 반환되고 lease/claim은 정리되며 provider outcome은 terminal projection을 바꾸지 않는다.
    @Test
    func `provider terminal CAS loss adopts host terminal before heartbeat`() async throws {
        let fixture = makeUncooperativeProviderCASFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)

        let recorder = ResumeProbeRecorder()
        let resume = startResume(on: fixture.plane, host: fixture.host, recorder: recorder)
        await fixture.store.waitForSaveCount(3)
        await fixture.clock.waitUntilSleeping()

        let hostPlane = RuntimeControlPlane(
            store: fixture.store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: fixture.clock.runtimeClock,
        )
        let hostTerminal = try #require(try await hostPlane.ingestHostEvent(fixture.hostTerminal))
        #expect(hostTerminal == RuntimeResult(
            runReference: fixture.run,
            outcome: .completed,
            artifactReferences: [],
        ))
        await fixture.providerApplyGate.open()

        let returned = await recorder.waitForValue()
        #expect(returned)
        #expect(await recorder.value == .result(hostTerminal))
        await fixture.clock.releaseSleepers()
        _ = await resume.value
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(await fixture.plane.projection(for: fixture.host) == .completed)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.plane.acceptedEventCount(for: fixture.host) == 0)
        let persisted = try #require(await fixture.store.currentState()?.sessions.first)
        #expect(persisted.projection == .completed)
        #expect(persisted.restorationClaim == nil)
        #expect(await fixture.store.applyCount == 4)
        #expect(await fixture.store.loadCount == 3)
        let counts = await fixture.adapter.counts()
        #expect(counts.launch == 0)
        #expect(counts.stream == 1)
        #expect(counts.terminalResult == 0)
    }
}

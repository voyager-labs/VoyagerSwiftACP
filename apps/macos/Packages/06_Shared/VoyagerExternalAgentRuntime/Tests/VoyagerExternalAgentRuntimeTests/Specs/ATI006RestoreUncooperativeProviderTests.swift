import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - ATI-006-restore_launch_heartbeat_race

    /// ATI-006-restore_launch_heartbeat_race: same-run host terminal wins while restored adapter launch is blocked.
    /// 복원 adapter launch가 gate에서 멈춰도 heartbeat가 host terminal을 채택하고 late receipt를 차단하는지 검증한다.
    /// - 검증 내용: controlled renewal, exact attempt ownership, one launch, late receipt 무변경.
    /// - 사전 조건: restored claim이 있고 adapter launch가 deterministic gate에서 대기한다.
    /// - 기대 결과: host terminal이 먼저 반환되고 gate 해제 뒤 receipt가 상태를 변경하지 않는다.
    @Test
    func `same run host terminal wins while restored launch is blocked`() async throws {
        let fixture = makeUncooperativeProviderLaunchFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)

        let recorder = ResumeProbeRecorder()
        let resume = startResume(on: fixture.plane, host: fixture.host, recorder: recorder)
        await fixture.adapter.waitForLaunchCount(1)
        await fixture.launchGate.waitUntilWaiting()
        await fixture.clock.waitUntilSleeping()
        fixture.clock.advance(by: 60)

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
        #expect(await fixture.adapter.counts().launch == 1)

        await fixture.launchGate.open()
        _ = await resume.value
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        #expect(await fixture.plane.projection(for: fixture.host) == .completed)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim == nil)
        #expect(await fixture.adapter.counts().launch == 1)
    }

    // MARK: - ATI-006-restore_launch_cancellation

    /// ATI-006-restore_launch_cancellation: caller cancellation preserves CancellationError during blocked launch.
    /// blocked launch 취소가 adapterUnavailable로 정규화되지 않고 exact claim을 복구하는지 검증한다.
    /// - 검증 내용: exact CancellationError, restored claim, later retry success, no duplicate launch.
    /// - 사전 조건: restored adapter launch가 gate에서 대기하고 caller가 resume을 취소한다.
    /// - 기대 결과: 첫 호출은 CancellationError로 끝나고 claim 복구 뒤 retry가 completed로 성공한다.
    @Test
    func `blocked restored launch cancellation restores claim for retry`() async throws {
        let fixture = makeUncooperativeProviderLaunchFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)

        let firstRecorder = ResumeProbeRecorder()
        let firstResume = startResume(on: fixture.plane, host: fixture.host, recorder: firstRecorder)
        await fixture.adapter.waitForLaunchCount(1)
        await fixture.launchGate.waitUntilWaiting()
        firstResume.cancel()
        #expect(await firstRecorder.waitForValue())
        #expect(await firstRecorder.value == .cancellation)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == .restored(1))
        let ownerToken = await fixture.plane.restorationOwnerToken
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim?.ownerToken == ownerToken)

        let secondRecorder = ResumeProbeRecorder()
        let secondResume = startResume(on: fixture.plane, host: fixture.host, recorder: secondRecorder)
        await fixture.adapter.waitForLaunchCount(2)
        await fixture.launchGate.open()
        #expect(await secondRecorder.waitForValue())
        #expect(await secondRecorder.value == .result(RuntimeResult(
            runReference: fixture.run,
            outcome: .completed,
            artifactReferences: [],
        )))
        _ = await firstResume.value
        _ = await secondResume.value
        #expect(await fixture.adapter.counts().launch == 2)
    }

    // MARK: - ATI-006-restore_launch_buffered_cancellation

    /// ATI-006-restore_launch_buffered_cancellation: buffered launch cannot hide caller cancellation.
    /// launch receipt가 race buffer에 도착한 cancellation 경계에서도 provider run을 회수하는지 검증한다.
    /// - 검증 내용: CancellationError, one exact cancellation request, no stream or retained context.
    /// - 사전 조건: restored launch gate가 receipt 반환 직전까지 열리지 않는다.
    /// - 기대 결과: caller 취소가 우선하고 provider consumption 없이 claim/context가 정리된다.
    @Test
    func `buffered launch cancellation rolls back launched receipt`() async throws {
        let trigger = ResumeCancellationTrigger()
        let fixture = makeUncooperativeProviderLaunchFixture(onLaunchReceiptReady: {
            Task { await trigger.cancel() }
        }, ignoresLaunchCancellation: true)
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)
        let recorder = ResumeProbeRecorder()
        let resume = startResume(on: fixture.plane, host: fixture.host, recorder: recorder)
        await trigger.set(resume)
        await fixture.adapter.waitForLaunchCount(1)
        await fixture.launchGate.open()
        #expect(await recorder.waitForValue())
        #expect(await recorder.value == .cancellation)
        #expect(await fixture.adapter.counts().cancellation == 1)
        #expect(await fixture.adapter.receivedCancellationRequests().first?.runReference == fixture.run)
        _ = await resume.value
        #expect(await fixture.adapter.counts().stream == 0)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == .restored(1))
    }

    // MARK: - ATI-006-restore_launch_receipt_mismatch

    /// ATI-006-restore_launch_receipt_mismatch: mismatched receipt is cancelled before Shared cleanup.
    /// post-launch receipt mismatch가 provider run을 남기지 않고 exact rollback을 수행하는지 검증한다.
    /// - 검증 내용: one rollback request with launched run, zero stream consumption, no validated context.
    /// - 사전 조건: adapter가 persisted run과 다른 receipt run을 반환한다.
    /// - 기대 결과: restartIncompatible와 rollback이 발생하고 Shared claim/context가 보존되지 않는다.
    @Test
    func `mismatched restored receipt is rolled back before cleanup`() async throws {
        let fixture = makeUncooperativeProviderLaunchFixture(launchReceiptRunReference: RuntimeRunReference("late-run"))
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)
        await fixture.launchGate.open()
        await #expect(throws: RuntimeHostError.restartIncompatible) {
            _ = try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        }
        #expect(await fixture.adapter.counts().cancellation == 1)
        #expect(await fixture.adapter.receivedCancellationRequests().first?
            .runReference == RuntimeRunReference("late-run"))
        #expect(await fixture.adapter.counts().stream == 0)
        #expect(await fixture.plane.validatedRestoreContexts[fixture.host] == nil)
    }

    // MARK: - ATI-006-restore_launch_stale_retry

    /// ATI-006-restore_launch_stale_retry: a first launch completion cannot clear a newer retry.
    /// 첫 attempt의 늦은 launch completion이 같은 lease를 재사용한 retry의 소유권을 덮어쓰지 않는지 검증한다.
    /// - 검증 내용: second attempt completion, exact launch count, final claim/context ownership.
    /// - 사전 조건: 첫 attempt는 receipt 경계에서 취소되고 즉시 같은 run retry가 시작된다.
    /// - 기대 결과: retry만 provider consumption을 수행하고 completed로 종료한다.
    @Test
    func `stale first launch completion cannot clear newer retry`() async throws {
        let trigger = ResumeCancellationTrigger()
        let fixture = makeUncooperativeProviderLaunchFixture(onLaunchReceiptReady: {
            Task { await trigger.cancel() }
        })
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)
        let firstRecorder = ResumeProbeRecorder()
        let first = startResume(on: fixture.plane, host: fixture.host, recorder: firstRecorder)
        await trigger.set(first)
        await fixture.adapter.waitForLaunchCount(1)
        await fixture.launchGate.open()
        #expect(await firstRecorder.waitForValue())
        #expect(await firstRecorder.value == .cancellation)

        let secondRecorder = ResumeProbeRecorder()
        let second = startResume(on: fixture.plane, host: fixture.host, recorder: secondRecorder)
        await fixture.adapter.waitForLaunchCount(2)
        #expect(await secondRecorder.waitForValue())
        #expect(await secondRecorder.value == .result(RuntimeResult(
            runReference: fixture.run,
            outcome: .completed,
            artifactReferences: [],
        )))
        _ = await first.value
        _ = await second.value
        #expect(await fixture.plane.validatedRestoreContexts[fixture.host] == nil)
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim == nil)
    }

    // MARK: - ATI-006-restore_launch_abandoned

    /// ATI-006-restore_launch_abandoned: pre-receipt cancellation converges before retry.
    /// - 검증 내용: exact cancellation and same-run retry after operation cleanup.
    /// - 사전 조건: first launch is blocked before its receipt.
    /// - 기대 결과: cancellation restores the claim and the retry completes.
    @Test
    func `abandoned pre-receipt launch blocks retry until rollback`() async throws {
        let fixture = makeUncooperativeProviderLaunchFixture()
        try await fixture.plane.register(fixture.adapter)
        #expect(try await fixture.plane
            .restore(hostReference: fixture.host, expectedContext: fixture.context) == .restored)
        let first = Task {
            try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        }
        await fixture.adapter.waitForLaunchCount(1)
        first.cancel()
        await fixture.adapter.waitForCancellationCount(1)
        await #expect(throws: CancellationError.self) { _ = try await first.value }
        #expect(await fixture.adapter.receivedCancellationRequests().first?.runReference == fixture.run)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == .restored(1))
        let ownerToken = await fixture.plane.restorationOwnerToken
        #expect(await fixture.plane.sessions[fixture.host]?.stored.restorationClaim?.ownerToken == ownerToken)
        let retry = try await fixture.plane.resumeRestoredRun(hostReference: fixture.host)
        #expect(retry.outcome == .completed)
        #expect(await fixture.adapter.counts().launch == 2)
        #expect(await fixture.adapter.counts().stream == 1)
    }

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
        #expect(counts.launch == 1)
        #expect(counts.stream == 1)
        #expect(counts.terminalResult == 0)
    }
}

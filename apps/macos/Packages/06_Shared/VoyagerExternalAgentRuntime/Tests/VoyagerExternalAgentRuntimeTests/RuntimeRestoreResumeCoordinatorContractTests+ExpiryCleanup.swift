import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeRestoreResumeCoordinatorContractTests {
    /// VOY-747-review_p1_2: cleanup persistence failure releases an expired local resumption owner.
    /// caller cancellation 중 만료 claim clear 저장이 실패해도 정확한 local run/lease만 비활성화하는지 검증한다.
    /// - 검증 내용: exact CancellationError, durable expired claim 보존, cleanup evidence, local lease 비활성화, immediate
    /// restore 재획득.
    /// - 사전 조건: resume claim 저장 뒤 clock이 만료 시점으로 전진하고 세 번째 state apply가 persistence failure를 반환한다.
    /// - 기대 결과: 취소 분류는 유지되고 local owner가 해제되어 다음 restore가 activeRunExists 없이 성공한다.
    @Test
    func `expired cleanup persistence failure releases cancelled resumption owner`() async throws {
        let fixture = expiryCleanupFailureFixture()
        try await fixture.plane.register(fixture.adapter)

        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        let resume = Task { try await fixture.plane.resumeRestoredRun(hostReference: fixture.host) }
        await fixture.adapter.waitForEventStreamCount(1)
        await fixture.clock.waitUntilSleeping()
        fixture.clock.advance(by: 60)
        resume.cancel()
        await fixture.streamGate.open()

        await #expect(throws: CancellationError.self) { try await resume.value }
        #expect(await fixture.store.currentState()?.sessions.first?.restorationClaim != nil)
        #expect(await fixture.plane.sessions[fixture.host]?.lease == RuntimeControlPlane.RuntimeLease.none)
        #expect(await fixture.plane.cleanupFailureEvidence(for: fixture.host) == RuntimeCleanupFailureEvidence(
            runReference: fixture.run,
            kind: .persistence,
        ))
        #expect(try await fixture.plane.restore(
            hostReference: fixture.host,
            expectedContext: fixture.context,
        ) == .restored)
        #expect(await fixture.adapter.counts().stream == 1)
        #expect(await fixture.adapter.counts().terminalResult == 0)
    }
}

private struct ExpiryCleanupFailureFixture {
    let clock: DeterministicRuntimeRestorationClock
    let streamGate: RuntimeTestGate
    let host: ExternalAgentSessionReference
    let run: RuntimeRunReference
    let context: RuntimeContextPolicy
    let store: InMemoryRuntimeStateStore
    let adapter: DeterministicRuntimeAdapter
    let plane: RuntimeControlPlane
}

private func expiryCleanupFailureFixture() -> ExpiryCleanupFailureFixture {
    let clock = DeterministicRuntimeRestorationClock(
        currentDate: Date(timeIntervalSince1970: 4_102_444_800),
    )
    let streamGate = RuntimeTestGate()
    let host: ExternalAgentSessionReference = "review-p1-2-cleanup-failure-host"
    let run = RuntimeRunReference("review-p1-2-cleanup-failure-run")
    let context = makeContext()
    let capabilities = expiryCleanupStreamOnlyCapabilities()
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: context),
        externalAgentSessionReference: host,
        providerInternalSessionReference: ProviderInternalSessionReference(
            "review-p1-2-cleanup-failure-receipt",
        ),
        runReference: run,
        capabilitySnapshot: capabilities,
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        failingSaveNumbers: [3],
    )
    let adapter = DeterministicRuntimeAdapter(
        id: "sdk",
        transport: .sdkAsyncStream,
        capabilities: capabilities,
        eventsByLaunch: [[]],
        eventStreamGate: streamGate,
    )
    return ExpiryCleanupFailureFixture(
        clock: clock,
        streamGate: streamGate,
        host: host,
        run: run,
        context: context,
        store: store,
        adapter: adapter,
        plane: RuntimeControlPlane(
            store: store,
            restorationHeartbeatInterval: .seconds(20),
            restorationClock: clock.runtimeClock,
        ),
    )
}

private func expiryCleanupStreamOnlyCapabilities() -> RuntimeCapabilities {
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

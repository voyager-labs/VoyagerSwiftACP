import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

@Suite("RuntimeRestoreResumeCoordinatorContractTests")
struct RuntimeRestoreResumeCoordinatorContractTests {
    // MARK: - VOY-747-restore_claim_matrix

    /// VOY-747-restore_claim_matrix: restore/resume table rows are exhaustive across claims, leases, and projections.
    /// 복원 claim 정책이 시간 파생 결과와 runtime lease를 빠짐없이 순수 결정으로 매핑하는지 검증한다.
    /// - 검증 내용: 네 claim 상태, 일곱 signal, 모든 runtime lease, terminal/nonterminal projection과 persisted conflict.
    /// - 사전 조건: persisted claim의 Date 비교는 호출자 경계에서 ClaimState로 변환되어 Snapshot에 주입된다.
    /// - 기대 결과: 각 row가 stale, claim/lease 전이, persisted adoption, 또는 typed host error 중 하나로 결정된다.
    @Test
    func `decision table covers restore claim rows`() {
        assertTerminalRows()
        assertNonterminalLeaseRows()
        assertClaimAcquisitionRows()
        assertBeginResumeRows()
        assertHeartbeatRows()
    }

    private func assertTerminalRows() {
        let signals: [RuntimeRestoreResumeDecisionTable.Signal] = [
            .evaluateRestore, .acquireClaim, .beginResume, .heartbeat,
            .claimLost, .restoreAfterFailure,
        ]
        for projection in [
            RuntimeProjection.launchBlocked, .launchCancelled, .launchFailed,
            .completed, .failed, .interrupted,
        ] {
            for lease in allLeases {
                for claim in allClaimStates {
                    let snapshot = RuntimeRestoreResumeDecisionTable.Snapshot(
                        projection: projection,
                        lease: lease,
                        claimState: claim,
                    )
                    #expect(RuntimeRestoreResumeDecisionTable.decide(.persistConflict, on: snapshot) == .adoptPersisted)
                    for signal in signals {
                        #expect(RuntimeRestoreResumeDecisionTable.decide(signal, on: snapshot) == .stale)
                    }
                }
            }
        }
    }

    private func assertNonterminalLeaseRows() {
        for projection in [
            RuntimeProjection.policyPending, .policyReady, .launching, .running,
            .eventProjected, .eventDuplicateIgnored, .eventOutOfOrder,
        ] {
            for lease in allLeases {
                let snapshot = RuntimeRestoreResumeDecisionTable.Snapshot(
                    projection: projection,
                    lease: lease,
                    claimState: .absent,
                )
                let expected: RuntimeRestoreResumeDecisionTable.Decision = lease == .none
                    ? .acquireClaim
                    : .throwHost(.activeRunExists)
                #expect(RuntimeRestoreResumeDecisionTable.decide(.evaluateRestore, on: snapshot) == expected)
                #expect(RuntimeRestoreResumeDecisionTable.decide(.acquireClaim, on: snapshot) == expected)
            }
        }
    }

    private func assertClaimAcquisitionRows() {
        for claim in allClaimStates {
            let snapshot = RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: .running,
                lease: .none,
                claimState: claim,
            )
            let expected: RuntimeRestoreResumeDecisionTable.Decision = claim == .foreignLive
                ? .stale
                : .acquireClaim
            #expect(RuntimeRestoreResumeDecisionTable.decide(.evaluateRestore, on: snapshot) == expected)
            #expect(RuntimeRestoreResumeDecisionTable.decide(.acquireClaim, on: snapshot) == expected)
        }
    }

    private func assertBeginResumeRows() {
        for claim in allClaimStates {
            let snapshot = RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: .running,
                lease: .restored(1),
                claimState: claim,
            )
            let expected: RuntimeRestoreResumeDecisionTable.Decision = switch claim {
            case .ownedLive:
                .beginResume
            case .foreignLive:
                .stale
            case .absent, .expired:
                .restoreClaim
            }
            #expect(RuntimeRestoreResumeDecisionTable.decide(.beginResume, on: snapshot) == expected)
            let claimLostExpected: RuntimeRestoreResumeDecisionTable.Decision = claim == .foreignLive
                ? .stale
                : .restoreClaim
            #expect(RuntimeRestoreResumeDecisionTable.decide(.claimLost, on: snapshot) == claimLostExpected)
        }
    }

    private func assertHeartbeatRows() {
        for claim in allClaimStates {
            let snapshot = RuntimeRestoreResumeDecisionTable.Snapshot(
                projection: .eventProjected,
                lease: .resuming(1),
                claimState: claim,
            )
            let expected: RuntimeRestoreResumeDecisionTable.Decision = switch claim {
            case .ownedLive:
                .renewClaim
            case .foreignLive:
                .stale
            case .absent, .expired:
                .restoreClaim
            }
            #expect(RuntimeRestoreResumeDecisionTable.decide(.heartbeat, on: snapshot) == expected)
            #expect(RuntimeRestoreResumeDecisionTable.decide(.restoreAfterFailure, on: snapshot) == (
                claim == .foreignLive ? .stale : .restoreClaim
            ))
        }
    }

    private var allClaimStates: [RuntimeRestoreResumeDecisionTable.ClaimState] {
        [.absent, .ownedLive, .foreignLive, .expired]
    }

    private var allLeases: [RuntimeControlPlane.RuntimeLease] {
        [
            .none,
            .launching(1),
            .detachedLaunching(2),
            .consuming(3),
            .detachedConsuming(4),
            .restored(5),
            .resuming(6),
        ]
    }
}

// MARK: - VOY-747-restore_claim_acquisition

/// VOY-747-restore_claim_acquisition: compatible restore persists a single claim before any provider consumption.
/// 호환 가능한 복원이 restart compatibility 이후 단일 claim CAS만 수행하는지 public coordinator 경계에서 검증한다.
/// - 검증 내용: claim owner/expiry, apply 횟수, restartCompatibility/eventStream/terminalResult 호출 횟수.
/// - 사전 조건: claim 없는 running session과 injected restoration clock이 구성되어 있다.
/// - 기대 결과: restored와 정확히 하나의 persisted claim을 얻고 provider resume 호출은 0회다.
@Test
func `compatible restore acquires one claim before provider resume`() async throws {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "compatible-claim"
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        externalAgentSessionReference: host,
        runReference: RuntimeRunReference("compatible-claim-run"),
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = DeterministicRuntimeAdapter(id: "sdk")
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    try await plane.register(adapter)

    #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .restored)
    let persisted = try #require(await store.currentState()?.sessions.first)
    let claim = try #require(persisted.restorationClaim)
    let ownerToken = await plane.restorationOwnerToken
    let counts = await adapter.counts()

    #expect(claim.ownerToken == ownerToken)
    #expect(claim.expiresAt == now.addingTimeInterval(60))
    #expect(await store.applyCount == 1)
    #expect(await adapter.receivedRestartBindings().count == 1)
    #expect(counts.stream == 0)
    #expect(counts.terminalResult == 0)
}

/// VOY-747-restore_claim_acquisition: context mismatch never mints a claim or consumes provider results.
/// persisted context가 달라진 복원은 compatibility와 claim 획득 전에 stale로 종료되는지 검증한다.
/// - 검증 내용: stale 결과, claim 제거, restartCompatibility/eventStream/terminalResult 호출 횟수.
/// - 사전 조건: 저장 context와 요청 context의 local correlation이 다르다.
/// - 기대 결과: provider resume 호출과 claim mint가 모두 발생하지 않는다.
@Test
func `context mismatch never mints claim or calls provider`() async throws {
    let host: ExternalAgentSessionReference = "context-mismatch-claim"
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        externalAgentSessionReference: host,
        runReference: RuntimeRunReference("context-mismatch-claim-run"),
        projection: .running,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = DeterministicRuntimeAdapter(id: "sdk")
    let plane = RuntimeControlPlane(store: store)
    try await plane.register(adapter)
    let mismatch = RuntimeContextPolicy(
        branchReference: "feat-voy-696",
        authorizationGeneration: 1,
        localCorrelation: "different-correlation",
    )

    #expect(try await plane.restore(hostReference: host, expectedContext: mismatch) == .stale)
    let persisted = try #require(await store.currentState()?.sessions.first)
    let counts = await adapter.counts()

    #expect(persisted.restorationClaim == nil)
    #expect(await adapter.receivedRestartBindings().isEmpty)
    #expect(counts.stream == 0)
    #expect(counts.terminalResult == 0)
}

/// VOY-747-restore_claim_acquisition: foreign live claim is stale without a persistence mutation.
/// 다른 owner의 유효한 claim은 local metadata와 provider 경계를 건드리지 않고 stale로 수렴하는지 검증한다.
/// - 검증 내용: stale 결과, 원래 claim 보존, apply/restartCompatibility/eventStream/terminalResult 호출 횟수.
/// - 사전 조건: injected now보다 60초 뒤에 만료되는 foreign claim이 저장되어 있다.
/// - 기대 결과: claim CAS와 provider resume이 모두 발생하지 않는다.
@Test
func `foreign live claim remains stale`() async throws {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "foreign-live-claim"
    let foreignClaim = RuntimeRestorationClaim(
        ownerToken: "foreign-owner",
        expiresAt: now.addingTimeInterval(60),
    )
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        externalAgentSessionReference: host,
        runReference: RuntimeRunReference("foreign-live-claim-run"),
        projection: .running,
        restorationClaim: foreignClaim,
    )
    let store = InMemoryRuntimeStateStore(state: makeState([stored]))
    let adapter = DeterministicRuntimeAdapter(id: "sdk")
    let plane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    try await plane.register(adapter)

    #expect(try await plane.restore(hostReference: host, expectedContext: makeContext()) == .stale)
    let persisted = try #require(await store.currentState()?.sessions.first)
    let counts = await adapter.counts()

    #expect(persisted.restorationClaim == foreignClaim)
    #expect(await store.applyCount == 0)
    #expect(await adapter.receivedRestartBindings().isEmpty)
    #expect(counts.stream == 0)
    #expect(counts.terminalResult == 0)
}

// MARK: - VOY-747-restoration_clock

/// VOY-747-restoration_clock: injected restoration time and cancellation-aware sleep stay deterministic.
/// wall-clock과 실제 대기 없이 restoration clock의 time vector 및 취소 전파를 검증한다.
/// - 검증 내용: 현재 시각, 60초 전진 vector, sleeper release와 취소된 waiter의 종료.
/// - 사전 조건: 고정 Date와 deterministic sleeper가 구성되어 있다.
/// - 기대 결과: now는 고정되고 전진은 순수하며 sleep은 release되거나 CancellationError로 종료된다.
@Test
func `restoration clock vectors are deterministic`() async throws {
    let initial = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: initial)
    #expect(clock.runtimeClock.now() == initial)
    #expect(clock.advanced(by: 60).runtimeClock.now() == initial.addingTimeInterval(60))
    #expect(runtimeRestoreClaimState(nil, ownerToken: "owner", now: initial) == .absent)
    #expect(runtimeRestoreClaimState(
        RuntimeRestorationClaim(ownerToken: "owner", expiresAt: initial.addingTimeInterval(1)),
        ownerToken: "owner",
        now: initial,
    ) == .ownedLive)
    #expect(runtimeRestoreClaimState(
        RuntimeRestorationClaim(ownerToken: "other", expiresAt: initial.addingTimeInterval(1)),
        ownerToken: "owner",
        now: initial,
    ) == .foreignLive)
    #expect(runtimeRestoreClaimState(
        RuntimeRestorationClaim(ownerToken: "owner", expiresAt: initial),
        ownerToken: "owner",
        now: initial,
    ) == .expired)
    #expect(runtimeRestoreClaimState(
        RuntimeRestorationClaim(ownerToken: "owner", expiresAt: initial.addingTimeInterval(-1)),
        ownerToken: "owner",
        now: initial,
    ) == .expired)

    let releasedSleep = Task {
        try await clock.runtimeClock.sleep(.seconds(20))
    }
    await clock.waitUntilSleeping()
    await clock.releaseSleepers()
    try await releasedSleep.value

    let cancelledSleep = Task {
        try await clock.runtimeClock.sleep(.seconds(20))
    }
    await clock.waitUntilSleeping()
    cancelledSleep.cancel()
    await #expect(throws: CancellationError.self) {
        try await cancelledSleep.value
    }
}

// MARK: - VOY-747-future_coordinator

/// VOY-747-future_coordinator: an injected expired claim admits exactly one replacement owner.
/// deterministic now 기준으로 만료된 기존 claim을 두 복원 coordinator가 경쟁할 때 단일 승자를 검증한다.
/// - 검증 내용: 두 plane의 restore 결과와 replacement claim 경쟁 결과.
/// - 사전 조건: 실제 wall-clock보다 미래인 injected now와 그 기준으로 만료된 foreign claim이 저장되어 있다.
/// - 기대 결과: 한 plane만 restored를 얻고 다른 plane은 stale로 수렴한다.
@Test
func `expired claim admits exactly one replacement owner`() async throws {
    let fixture = makeExpiredClaimRaceFixture()
    try await fixture.firstPlane.register(fixture.firstAdapter)
    try await fixture.secondPlane.register(fixture.secondAdapter)

    let results = try await restoreExpiredClaimConcurrently(
        firstPlane: fixture.firstPlane,
        secondPlane: fixture.secondPlane,
        store: fixture.store,
        hydrationGate: fixture.hydrationGate,
        host: fixture.host,
    )

    let persisted = try #require(await fixture.store.currentState()?.sessions.first)
    let claim = try #require(persisted.restorationClaim)
    let firstOwner = await fixture.firstPlane.restorationOwnerToken
    let secondOwner = await fixture.secondPlane.restorationOwnerToken
    let firstCounts = await fixture.firstAdapter.counts()
    let secondCounts = await fixture.secondAdapter.counts()
    let bindingCounts = await (
        fixture.firstAdapter.receivedRestartBindings().count,
        fixture.secondAdapter.receivedRestartBindings().count,
    )

    expectExpiredClaimRace(
        results: results,
        claim: claim,
        ownerTokens: [firstOwner, secondOwner],
        counts: (firstCounts, secondCounts),
        bindingCounts: bindingCounts,
    )
    #expect(await fixture.store.applyCount == 2)
    #expect(await fixture.firstPlane.projection(for: fixture.host) == .running)
    #expect(await fixture.secondPlane.projection(for: fixture.host) == .running)
}

private struct ExpiredClaimRaceFixture {
    let host: ExternalAgentSessionReference
    let store: InMemoryRuntimeStateStore
    let hydrationGate: RuntimeTestGate
    let firstPlane: RuntimeControlPlane
    let secondPlane: RuntimeControlPlane
    let firstAdapter: DeterministicRuntimeAdapter
    let secondAdapter: DeterministicRuntimeAdapter
}

private func makeExpiredClaimRaceFixture() -> ExpiredClaimRaceFixture {
    let now = Date(timeIntervalSince1970: 4_102_444_800)
    let clock = DeterministicRuntimeRestorationClock(currentDate: now)
    let host: ExternalAgentSessionReference = "future-expired-claim"
    let stored = makeEqualitySession(
        storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
        externalAgentSessionReference: host,
        runReference: RuntimeRunReference("future-expired-claim-run"),
        projection: .running,
        restorationClaim: RuntimeRestorationClaim(
            ownerToken: "previous-owner",
            expiresAt: now.addingTimeInterval(-1),
        ),
    )
    let hydrationGate = RuntimeTestGate()
    let store = InMemoryRuntimeStateStore(
        state: makeState([stored]),
        loadGates: [1: hydrationGate, 2: hydrationGate],
    )
    let firstPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    let secondPlane = RuntimeControlPlane(
        store: store,
        restorationHeartbeatInterval: .seconds(20),
        restorationClock: clock.runtimeClock,
    )
    return ExpiredClaimRaceFixture(
        host: host,
        store: store,
        hydrationGate: hydrationGate,
        firstPlane: firstPlane,
        secondPlane: secondPlane,
        firstAdapter: DeterministicRuntimeAdapter(id: "sdk"),
        secondAdapter: DeterministicRuntimeAdapter(id: "sdk"),
    )
}

private func restoreExpiredClaimConcurrently(
    firstPlane: RuntimeControlPlane,
    secondPlane: RuntimeControlPlane,
    store: InMemoryRuntimeStateStore,
    hydrationGate: RuntimeTestGate,
    host: ExternalAgentSessionReference,
) async throws -> [RuntimeRestoreResult] {
    let first = Task {
        try await firstPlane.restore(hostReference: host, expectedContext: makeContext())
    }
    let second = Task {
        try await secondPlane.restore(hostReference: host, expectedContext: makeContext())
    }
    await store.waitForLoadCount(2)
    await hydrationGate.open()
    return try await [first.value, second.value]
}

private func expectExpiredClaimRace(
    results: [RuntimeRestoreResult],
    claim: RuntimeRestorationClaim,
    ownerTokens: [String],
    counts: (RuntimeAdapterInvocationCounts, RuntimeAdapterInvocationCounts),
    bindingCounts: (Int, Int),
) {
    #expect(results.count(where: { $0 == .restored }) == 1)
    #expect(results.count(where: { $0 == .stale }) == 1)
    #expect(ownerTokens.contains(claim.ownerToken))
    #expect(counts.0.stream == 0)
    #expect(counts.0.terminalResult == 0)
    #expect(counts.1.stream == 0)
    #expect(counts.1.terminalResult == 0)
    #expect(bindingCounts.0 == 1)
    #expect(bindingCounts.1 == 1)
}

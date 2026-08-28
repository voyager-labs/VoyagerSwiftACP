import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    // MARK: - VOY-696-terminal_retirement

    /// VOY-696-terminal_retirement: retiring one exact host from a saturated terminal registry admits a new host.
    /// 512개 terminal 세션으로 포화된 레지스트리에서 정확한 호스트 하나를 은퇴시키면 새 호스트 prelaunch가 다시 허용되어야 한다.
    /// - 검증 내용: 포화 상태에서 새 호스트 prelaunch 거부, 은퇴 성공, durable/local 카운트 511, 재 prelaunch 성공과 카운트 512 복원.
    /// - 사전 조건: lease-none terminal 세션 512개가 저장되어 있고 새 호스트·새 run 요청이 준비되어 있다.
    /// - 기대 결과: 은퇴는 성공하고 새 호스트 prelaunch가 policyReady로 저장되며 총 세션 수는 512로 돌아온다.
    @Test
    func `full terminal registry admits a new host after one exact retirement`() async throws {
        let sessions = (0 ..< RuntimeBoundaryLimits.persistedSessions).map { index in
            makeRetirementTerminalSession(
                host: ExternalAgentSessionReference("host-retire-capacity-\(index)"),
                run: RuntimeRunReference("run-retire-capacity-\(index)"),
            )
        }
        let store = InMemoryRuntimeStateStore(state: makeState(sessions))
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(makeAdapter())
        let retiredHost = ExternalAgentSessionReference("host-retire-capacity-0")
        let newHost = ExternalAgentSessionReference("host-retire-capacity-new")
        let newRequest = makeLaunch(
            host: newHost,
            run: RuntimeRunReference("run-retire-capacity-new"),
            adapterID: "sdk",
        )

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            try await plane.projectPrelaunch(newRequest, as: .policyReady)
        }

        try await plane.retireTerminalSession(hostReference: retiredHost)
        let persistedAfterRetirement = try #require(await store.currentState())
        #expect(persistedAfterRetirement.sessions.count == RuntimeBoundaryLimits.persistedSessions - 1)
        #expect(await plane.sessions.count == RuntimeBoundaryLimits.persistedSessions - 1)

        try await plane.projectPrelaunch(newRequest, as: .policyReady)
        #expect(await plane.projection(for: newHost) == .policyReady)
        let persistedAfterAdmission = try #require(await store.currentState())
        #expect(persistedAfterAdmission.sessions.count == RuntimeBoundaryLimits.persistedSessions)
        #expect(await plane.sessions.count == RuntimeBoundaryLimits.persistedSessions)
    }

    /// VOY-696-terminal_retirement: absent host retirement is idempotent success without store apply.
    /// 없거나 이미 삭제된 호스트의 은퇴는 저장소 적용 없이 멱등하게 성공해야 한다.
    /// - 검증 내용: 두 번의 연속 은퇴 호출 모두 성공, apply 0회, 액터 로컬 보조 메타데이터 제거.
    /// - 사전 조건: 빈 저장소와 cleanup evidence·restored resume attempt 메타데이터가 남아 있는 평면.
    /// - 기대 결과: 어떤 store apply도 발생하지 않고 보조 메타데이터는 해당 호스트에서 사라진다.
    @Test
    func `absent host retirement is idempotent success without store apply`() async throws {
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.hydrateIfNeeded()
        let absentHost = ExternalAgentSessionReference("host-retire-absent")
        try await plane.mutateAfterPersistedTransitions { plane in
            plane.cleanupFailureEvidenceByHost[absentHost] = RuntimeCleanupFailureEvidence(
                runReference: RuntimeRunReference("run-retire-absent"),
                kind: .persistence,
            )
            plane.activeRestoredResumeAttempts[absentHost] = RuntimeRestoreResumeAttemptID(rawValue: 7)
        }

        try await plane.retireTerminalSession(hostReference: absentHost)
        try await plane.retireTerminalSession(hostReference: absentHost)

        #expect(await store.applyCount == 0)
        #expect(await plane.cleanupFailureEvidence(for: absentHost) == nil)
        #expect(await plane.activeRestoredResumeAttempts[absentHost] == nil)
    }

    /// VOY-696-terminal_retirement: a nonterminal lease-none session rejects retirement as invalid event.
    /// nonterminal 세션은 은퇴 대상이 아니므로 invalidEvent로 거부되고 어떤 상태 변화도 남기지 않아야 한다.
    /// - 검증 내용: invalidEvent, apply 0회, running projection과 세션 수 불변.
    /// - 사전 조건: lease-none running 세션 하나가 저장되어 있다.
    /// - 기대 결과: 은퇴는 거부되고 저장된 세션은 그대로 유지된다.
    @Test
    func `nonterminal lease-none session rejects retirement as invalid event`() async throws {
        let host = ExternalAgentSessionReference("host-retire-nonterminal")
        let run = RuntimeRunReference("run-retire-nonterminal")
        let live = RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: ProviderInternalSessionReference("opaque-retire-live"),
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            projection: .running,
        )
        let store = InMemoryRuntimeStateStore(state: makeState([live]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.hydrateIfNeeded()

        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.retireTerminalSession(hostReference: host)
        }

        #expect(await store.applyCount == 0)
        #expect(await plane.projection(for: host) == .running)
        #expect(try #require(await store.currentState()).sessions.count == 1)
    }

    /// VOY-696-terminal_retirement: a terminal session with an active consuming or resuming lease rejects retirement.
    /// terminal이라도 소유 lease가 활성인 세션은 복원·재개 자격이 있으므로 invalidEvent로 거부되어야 한다.
    /// - 검증 내용: consuming·resuming 각각 invalidEvent, apply 0회, lease와 세션 수 불변.
    /// - 사전 조건: terminal completed 세션이 저장되어 있고 액터 로컬 lease가 활성으로 설정되어 있다.
    /// - 기대 결과: 은퇴는 거부되고 활성 lease를 가진 세션은 보존된다.
    @Test(arguments: [
        ("consuming", RuntimeControlPlane.RuntimeLease.consuming(1)),
        ("resuming", RuntimeControlPlane.RuntimeLease.resuming(1)),
    ])
    func `terminal session with active lease rejects retirement as invalid event`(
        label: String,
        lease: RuntimeControlPlane.RuntimeLease,
    ) async throws {
        let host = ExternalAgentSessionReference("host-retire-active-\(label)")
        let run = RuntimeRunReference("run-retire-active-\(label)")
        let store = InMemoryRuntimeStateStore(state: makeState([
            makeRetirementTerminalSession(host: host, run: run),
        ]))
        let plane = RuntimeControlPlane(store: store)
        try await plane.hydrateIfNeeded()
        try await plane.mutateAfterPersistedTransitions { plane in
            var leased = try #require(plane.sessions[host])
            leased.lease = lease
            plane.sessions[host] = leased
        }

        await #expect(throws: RuntimeHostError.invalidEvent) {
            try await plane.retireTerminalSession(hostReference: host)
        }

        #expect(await store.applyCount == 0)
        #expect(await plane.sessions[host]?.lease == lease)
        #expect(try #require(await store.currentState()).sessions.count == 1)
    }

    /// VOY-696-terminal_retirement: a deletion raced by another plane converges as idempotent success.
    /// 다른 평면이 먼저 같은 호스트를 삭제한 뒤에는 CAS 충돌이 읽기 전용 재조정으로 성공 수렴해야 한다.
    /// - 검증 내용: 충돌 CAS 1회 후 성공, apply 총 2회로 재시도 없음, 저장소와 로컬 모두 해당 호스트 부재.
    /// - 사전 조건: 같은 저장소를 공유하는 선구평면이 호스트를 이미 은퇴시켰고 뒤평면은 stale terminal 사본을 가진다.
    /// - 기대 결과: 뒤평면의 은퇴는 persistenceConflict 없이 성공하고 어느 쪽에도 세션이 남지 않는다.
    @Test
    func `conflicting deletion by another plane converges retirement as success`() async throws {
        let host = ExternalAgentSessionReference("host-retire-race-delete")
        let run = RuntimeRunReference("run-retire-race-delete")
        let store = InMemoryRuntimeStateStore(state: makeState([
            makeRetirementTerminalSession(host: host, run: run),
        ]))
        let stalePlane = RuntimeControlPlane(store: store)
        try await stalePlane.hydrateIfNeeded()
        let deletingPlane = RuntimeControlPlane(store: store)
        try await deletingPlane.retireTerminalSession(hostReference: host)
        #expect(try #require(await store.currentState()).sessions.isEmpty)

        try await stalePlane.retireTerminalSession(hostReference: host)

        #expect(await store.applyCount == 2)
        #expect(try #require(await store.currentState()).sessions.isEmpty)
        #expect(await stalePlane.sessions[host] == nil)
    }

    /// VOY-696-terminal_retirement: a replacement run survives conflicting retirement and surfaces persistence
    /// conflict.
    /// 같은 호스트가 다른 run으로 교체된 뒤의 은퇴 충돌은 교체 세션을 보존하고 persistenceConflict를 전파해야 한다.
    /// - 검증 내용: persistenceConflict 전파, apply 총 2회로 재시도·블라인드 삭제 없음, 교체 run의 저장·로컬 보존.
    /// - 사전 조건: 선구평면이 같은 호스트를 새 run policyReady 세션으로 교체했고 뒤평면은 stale terminal 사본을 가진다.
    /// - 기대 결과: 교체 세션은 저장소와 로컬 모두에 유지되고 은퇴는 persistenceConflict로 실패한다.
    @Test
    func `replacement run survives conflicting retirement and surfaces persistence conflict`() async throws {
        let host = ExternalAgentSessionReference("host-retire-replaced")
        let originalRun = RuntimeRunReference("run-retire-replaced-original")
        let replacementRun = RuntimeRunReference("run-retire-replaced-replacement")
        let store = InMemoryRuntimeStateStore(state: makeState([
            makeRetirementTerminalSession(host: host, run: originalRun),
        ]))
        let stalePlane = RuntimeControlPlane(store: store)
        try await stalePlane.hydrateIfNeeded()
        let replacingPlane = RuntimeControlPlane(store: store)
        try await replacingPlane.register(makeAdapter())
        let replacementRequest = makeLaunch(host: host, run: replacementRun, adapterID: "sdk")
        try await replacingPlane.projectPrelaunch(replacementRequest, as: .policyReady)

        await #expect(throws: RuntimeHostError.persistenceConflict) {
            try await stalePlane.retireTerminalSession(hostReference: host)
        }

        #expect(await store.applyCount == 2)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.externalAgentSessionReference == host)
        #expect(persisted.runReference == replacementRun)
        #expect(persisted.projection == .policyReady)
        #expect(await stalePlane.projection(for: host) == .policyReady)
        #expect(await stalePlane.sessions[host]?.stored.runReference == replacementRun)
    }

    private func makeRetirementTerminalSession(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: makeContext()),
            projection: .completed,
        )
    }
}

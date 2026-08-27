import Foundation
import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    // MARK: - terminal-event-budget

    /// VOY-696-coordinator_contract: a novel exact host terminal converges at the accepted-event budget.
    /// 처리·수용 카운터가 상한에 도달한 실행에서도 새로운 exact terminal 이벤트는 예산 소진으로 거부되지 않고 수렴해야 한다.
    /// - 검증 내용: completed 결과 반환, durable completed projection, acceptedEventsPerRun에 포화된 processed/accepted 카운터.
    /// - 사전 조건: hostProcessedEventCount와 hostAcceptedEventCount가 정확히 10,000인 launching 세션이 저장되어 있다.
    /// - 기대 결과: terminal이 수용·저장되고 두 카운터는 상한에서 포화되며 초과하지 않는다.
    @Test
    func `saturated budget admits a novel exact host terminal`() async throws {
        let host = ExternalAgentSessionReference("host-budget-terminal")
        let run = RuntimeRunReference("run-budget-terminal")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [makeSaturatedHostSession(host: host, run: run, contextPolicy: request.contextPolicy)],
        ))
        let plane = RuntimeControlPlane(store: store)

        let result = try await plane.ingestHostEvent(makeBudgetHostEvent(
            host: host,
            run: run,
            sequence: UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) + 1,
            idempotencyKey: "host-budget-terminal-completed",
            kind: .completed,
        ))

        #expect(result?.outcome == .completed)
        #expect(await plane.projection(for: host) == .completed)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.projection == .completed)
        #expect(persisted.hostLastSequence == UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) + 1)
        #expect(persisted.hostAcceptedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(persisted.hostProcessedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
    }

    /// VOY-696-coordinator_contract: nonterminal progress stays fail-closed at the accepted-event budget.
    /// 예산이 포화된 상태에서 nonterminal progress 이벤트는 계속 거부되고 카운터를 넘어서 증가시키지 않는다.
    /// - 검증 내용: malformedAdapterResponse, 저장되지 않은 launching projection, 불변인 카운터와 apply 횟수.
    /// - 사전 조건: host 카운터가 정확히 10,000으로 포화된 launching 세션이 저장되어 있다.
    /// - 기대 결과: progress는 거부되고 어떤 저장 변화도 남지 않는다.
    @Test
    func `saturated budget keeps nonterminal progress fail-closed`() async throws {
        let host = ExternalAgentSessionReference("host-budget-progress")
        let run = RuntimeRunReference("run-budget-progress")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [makeSaturatedHostSession(host: host, run: run, contextPolicy: request.contextPolicy)],
        ))
        let plane = RuntimeControlPlane(store: store)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await plane.ingestHostEvent(makeBudgetHostEvent(
                host: host,
                run: run,
                sequence: UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) + 1,
                idempotencyKey: "host-budget-progress-novel",
                kind: .progress,
            ))
        }
        #expect(await plane.projection(for: host) == .launching)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.hostAcceptedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(persisted.hostProcessedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(await store.applyCount == 0)
    }

    /// VOY-696-coordinator_contract: duplicate replay stays bounded at the accepted-event budget.
    /// 이미 수용된 멱등키의 재전송은 예산 포화 상태에서 fail-closed로 거부되고 카운터를 넘치게 하지 않는다.
    /// - 검증 내용: malformedAdapterResponse, 불변인 포화 카운터와 apply 횟수.
    /// - 사전 조건: 수용된 멱등키 하나와 포화된 host 카운터를 가진 세션이 저장되어 있다.
    /// - 기대 결과: 중복 재전송은 거부되고 카운터는 acceptedEventsPerRun에 머문다.
    @Test
    func `saturated budget keeps duplicate replay bounded without counter overflow`() async throws {
        let host = ExternalAgentSessionReference("host-budget-duplicate")
        let run = RuntimeRunReference("run-budget-duplicate")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        var saturated = makeSaturatedHostSession(host: host, run: run, contextPolicy: request.contextPolicy)
        saturated = RuntimeStoredSession(
            externalAgentSessionReference: saturated.externalAgentSessionReference,
            providerInternalSessionReference: saturated.providerInternalSessionReference,
            runReference: saturated.runReference,
            adapterID: saturated.adapterID,
            adapterVersion: saturated.adapterVersion,
            capabilitySnapshot: saturated.capabilitySnapshot,
            storedContext: saturated.storedContext,
            projection: saturated.projection,
            providerLaunchAttempted: saturated.providerLaunchAttempted,
            lastSequence: saturated.lastSequence,
            acceptedEventCount: saturated.acceptedEventCount,
            processedEventCount: saturated.processedEventCount,
            acceptedIdempotencyKeys: saturated.acceptedIdempotencyKeys,
            hostLastSequence: saturated.hostLastSequence,
            hostAcceptedEventCount: saturated.hostAcceptedEventCount,
            hostProcessedEventCount: saturated.hostProcessedEventCount,
            hostAcceptedIdempotencyKeys: [RuntimeIdempotencyKey("host-budget-duplicate-seen")],
        )
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [saturated],
        ))
        let plane = RuntimeControlPlane(store: store)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await plane.ingestHostEvent(makeBudgetHostEvent(
                host: host,
                run: run,
                sequence: UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) + 1,
                idempotencyKey: "host-budget-duplicate-seen",
                kind: .progress,
            ))
        }
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.hostAcceptedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(persisted.hostProcessedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(await store.applyCount == 0)
    }

    /// VOY-696-coordinator_contract: stale and gap sequences stay bounded at the accepted-event budget.
    /// stale 시퀀스와 gap 증폭 시퀀스 모두 예산 포화 상태에서 fail-closed로 거부되고 카운터를 넘치게 하지 않는다.
    /// - 검증 내용: 각 시도의 malformedAdapterResponse, 불변인 포화 카운터와 apply 횟수.
    /// - 사전 조건: host 카운터가 정확히 10,000으로 포화된 launching 세션이 저장되어 있다.
    /// - 기대 결과: stale과 gap 시도 모두 거부되고 어떤 저장 변화도 남지 않는다.
    @Test
    func `saturated budget keeps stale and gap sequences bounded without counter overflow`() async throws {
        let host = ExternalAgentSessionReference("host-budget-stale-gap")
        let run = RuntimeRunReference("run-budget-stale-gap")
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        let store = InMemoryRuntimeStateStore(state: RuntimeStoredState(
            schemaVersion: RuntimeStoredState.currentSchemaVersion,
            sessions: [makeSaturatedHostSession(host: host, run: run, contextPolicy: request.contextPolicy)],
        ))
        let plane = RuntimeControlPlane(store: store)

        for sequence in [
            UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) - 1,
            UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun) * 5,
        ] {
            await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
                _ = try await plane.ingestHostEvent(makeBudgetHostEvent(
                    host: host,
                    run: run,
                    sequence: sequence,
                    idempotencyKey: "host-budget-stale-gap-\(sequence)",
                    kind: .progress,
                ))
            }
        }
        #expect(await plane.projection(for: host) == .launching)
        let persisted = try #require(await store.currentState()?.sessions.first)
        #expect(persisted.hostAcceptedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(persisted.hostProcessedEventCount == RuntimeBoundaryLimits.acceptedEventsPerRun)
        #expect(await store.applyCount == 0)
    }

    private func makeSaturatedHostSession(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        contextPolicy: RuntimeContextPolicy,
    ) -> RuntimeStoredSession {
        RuntimeStoredSession(
            externalAgentSessionReference: host,
            providerInternalSessionReference: nil,
            runReference: run,
            adapterID: RuntimeAdapterID("sdk"),
            adapterVersion: "1.0.0",
            capabilitySnapshot: .allSupported,
            storedContext: RuntimeStoredContext(contextPolicy: contextPolicy),
            projection: .launching,
            providerLaunchAttempted: true,
            lastSequence: 0,
            acceptedEventCount: 0,
            processedEventCount: 0,
            acceptedIdempotencyKeys: [],
            hostLastSequence: UInt64(RuntimeBoundaryLimits.acceptedEventsPerRun),
            hostAcceptedEventCount: RuntimeBoundaryLimits.acceptedEventsPerRun,
            hostProcessedEventCount: RuntimeBoundaryLimits.acceptedEventsPerRun,
            hostAcceptedIdempotencyKeys: [],
        )
    }

    private func makeBudgetHostEvent(
        host: ExternalAgentSessionReference,
        run: RuntimeRunReference,
        sequence: UInt64,
        idempotencyKey: String,
        kind: RuntimeEventKind,
    ) -> RuntimeEventEnvelope {
        RuntimeEventEnvelope(
            source: .host,
            providerEventID: ProviderEventID("host-\(idempotencyKey)"),
            sequence: sequence,
            idempotencyKey: RuntimeIdempotencyKey(idempotencyKey),
            timestamp: Date(timeIntervalSince1970: 1),
            externalAgentSessionReference: host,
            runReference: run,
            kind: kind,
        )
    }
}

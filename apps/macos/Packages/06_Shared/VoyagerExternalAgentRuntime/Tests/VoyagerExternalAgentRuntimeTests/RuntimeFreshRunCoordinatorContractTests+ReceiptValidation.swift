import Testing
@testable import VoyagerExternalAgentRuntime

extension RuntimeFreshRunCoordinatorContractTests {
    /// VOY-746-coordinator_contract: malformed receipt failure detaches the trusted request launch owner.
    /// 다른 runReference receipt의 검증 실패가 request run의 launching owner를 활성 상태로 남기지 않는지 검증한다.
    /// - 검증 내용: malformedAdapterResponse, nil receipt binding, detached launching lease와 provider launch count.
    /// - 사전 조건: policy-ready request와 다른 runReference를 반환하는 adapter가 있다.
    /// - 기대 결과: malformed receipt는 저장되지 않고 request run의 launch owner만 detached 상태로 회수된다.
    @Test
    func `malformed receipt validation failure releases request launch owner`() async throws {
        let host: ExternalAgentSessionReference = "host-contract-malformed-receipt-owner"
        let run = RuntimeRunReference("run-contract-malformed-receipt-owner")
        let mismatchedRun = RuntimeRunReference("run-contract-malformed-receipt-other")
        let adapter = DeterministicRuntimeAdapter(
            id: "sdk",
            transport: .sdkAsyncStream,
            eventsByLaunch: [[]],
            launchReceiptRunReference: mismatchedRun,
        )
        let store = InMemoryRuntimeStateStore()
        let plane = RuntimeControlPlane(store: store)
        try await plane.register(adapter)
        let request = makeLaunch(host: host, run: run, adapterID: "sdk")
        try await plane.projectPrelaunch(request, as: .policyReady)

        await #expect(throws: RuntimeHostError.malformedAdapterResponse) {
            _ = try await plane.run(request)
        }

        let session = try #require(await plane.sessions[host])
        #expect(session.stored.runReference == run)
        #expect(session.stored.projection == .launching)
        #expect(session.stored.providerInternalSessionReference == nil)
        guard case .detachedLaunching = session.lease else {
            Issue.record("malformed receipt 검증 실패 뒤 launch owner가 detachedLaunching이어야 한다: \(session.lease)")
            return
        }
        #expect(await store.currentState()?.sessions.first?.providerInternalSessionReference == nil)
        #expect(await adapter.counts().launch == 1)
    }
}

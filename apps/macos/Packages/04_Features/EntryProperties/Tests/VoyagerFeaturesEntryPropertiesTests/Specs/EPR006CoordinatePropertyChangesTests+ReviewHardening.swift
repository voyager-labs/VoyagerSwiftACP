import ComposableArchitecture
@testable import VoyagerEntryCoreClient
@testable import VoyagerFeaturesEntryProperties
import XCTest

@MainActor
extension EPR006CoordinatePropertyChangesTests {
    /// EPR-006-read_back_property_change_result: read-back 중 selection 변경은 pending 상태를 보존한다.
    /// - 검증 내용: 기존 read-back proposal, snapshot outcome과 generation fence
    /// - 사전 조건: mutation 적용 후 canonical read-back effect가 진행 중임
    /// - 기대 결과: 새 selection을 초기화하면서 읽기 전용 재시도 상태를 분리해 게시함
    func testSelectionChangeDuringReadBackPreservesPendingOutcomeAndFencesCompletion() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.appliedProposal = fixture.proposal
        state.activePhase = .applied
        state.status = .applied
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.selectionChanged(replacement)) {
            $0.generation = 1
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
            $0.activePhase = nil
            $0.appliedProposal = nil
            $0.pendingReadBack = fixture.proposal
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeAppliedUnverified(fixture.snapshot)
        }
        await store.receive(
            .init(kind: .outcome(.propertyChangeAppliedUnverified(fixture.snapshot))),
        )
        await store.send(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult))))
        XCTAssertEqual(store.state.selection, replacement)
        XCTAssertEqual(store.state.status, .idle)
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
        XCTAssertNil(store.state.canonicalResult)
    }

    /// EPR-006-read_back_property_change_result: pending read-back retry는 새 selection을 오염시키지 않는다.
    /// - 검증 내용: old snapshot의 retry 실행과 current selection 상태 격리
    /// - 사전 조건: selection 변경으로 pending read-back proposal이 보존됨
    /// - 기대 결과: old snapshot verified outcome은 발행하지만 current selection은 idle로 유지됨
    func testPendingReadBackRetryDoesNotContaminateCurrentSelection() async {
        let fixture = Fixture()
        let currentSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/current")],
            propertyID: fixture.selection.propertyID,
        )
        var state = EntryPropertiesState(selection: currentSelection)
        state.generation = 1
        state.pendingReadBack = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                readBack: { _ in fixture.canonicalResult },
            )
        }

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(1, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.canonicalResult = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertEqual(store.state.selection, currentSelection)
        XCTAssertEqual(store.state.status, .idle)
        XCTAssertNil(store.state.canonicalResult)
        XCTAssertNil(store.state.pendingReadBack)
    }

    /// EPR-006-execute_property_change: prepared 상태가 아니면 execute를 재전송하지 않는다.
    /// - 검증 내용: ambiguous/applied-unverified/verified 상태의 local rejection과 mutation 0회
    /// - 사전 조건: proposal은 남아 있지만 실행 phase가 terminal 또는 불확실 상태임
    /// - 기대 결과: stale outcome만 게시되고 각 상태와 proposal은 보존됨
    func testExecuteRequiresPreparedStatus() async {
        let fixture = Fixture()

        for status in [EntryPropertiesStatus.ambiguous, .appliedUnverified, .verified] {
            let recorder = OperationRecorder()
            var state = fixture.readyState
            state.proposal = fixture.proposal
            state.status = status
            let store = TestStore(initialState: state) {
                EntryPropertiesFeature()
            } withDependencies: {
                $0.entryPropertiesClient = fixture.client(execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                })
            }

            await store.send(.execute(confirmed: true)) {
                $0.lastOutcome = .propertyChangeRejected(.stale)
            }
            await store.receive(.init(kind: .outcome(.propertyChangeRejected(.stale))))
            XCTAssertEqual(store.state.status, status)
            XCTAssertEqual(store.state.proposal, fixture.proposal)
            let recordedOperations = await recorder.values()
            XCTAssertEqual(recordedOperations, [])
        }
    }

    /// EPR-006-prepare_property_change: applied-unverified 상태에서는 새 mutation을 시작하지 않는다.
    /// - 검증 내용: read-back 미검증 상태의 prepare busy rejection과 dependency 호출 0회
    /// - 사전 조건: trusted apply 뒤 canonical read-back이 실패해 현재 proposal이 applied-unverified로 남음
    /// - 기대 결과: read-only retry 경로를 보존하고 새 prepare를 시작하지 않음
    func testAppliedUnverifiedBlocksNewPrepare() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.status = .appliedUnverified
        state.appliedProposal = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(prepare: { _ in
                await recorder.record("prepare")
                return fixture.proposal
            })
        }

        await store.send(.prepare(fixture.intent)) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, [])
        XCTAssertEqual(store.state.status, .appliedUnverified)
        XCTAssertEqual(store.state.appliedProposal, fixture.proposal)
    }

    /// EPR-006-read_back_property_change_result: pending read-back이 있으면 새 mutation을 막는다.
    /// - 검증 내용: prepare/execute busy rejection과 dependency 호출 0회
    /// - 사전 조건: 이전 selection의 pending read-back proposal이 보존됨
    /// - 기대 결과: pending verification이 해소될 때까지 새 mutation이 시작되지 않음
    func testPendingReadBackBlocksNewMutation() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.pendingReadBack = fixture.proposal
        state.status = .prepared
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                prepare: { _ in
                    await recorder.record("prepare")
                    return fixture.proposal
                },
                execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                },
            )
        }

        await store.send(.prepare(fixture.intent)) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        await store.send(.execute(confirmed: true))
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, [])
    }

    /// EPR-006-prepare_property_change: Core proposal은 원 요청의 target/property/after를 그대로 반영해야 한다.
    /// - 검증 내용: 응답 target 불일치의 typed validation failure
    /// - 사전 조건: Core가 원 요청과 다른 prepared change를 반환함
    /// - 기대 결과: caller proposal을 만들지 않고 validation으로 fail closed
    func testPrepareRejectsMismatchedCoreProposal() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let desired = PropertyDesiredState.value(.text, .one, .text("after"))
        let response = try PropertyChangeProposal(
            changes: [
                PropertyPreparedChange(
                    target: PropertyTarget(localPath: "/wrong"),
                    propertyID: propertyID,
                    entryID: entryID,
                    before: nil,
                    after: desired,
                ),
            ],
            requiresConfirmation: true,
        )
        let propertyClient = mismatchedPropertyClient(response: response)
        let endpoint = try EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock")
        let client = EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: endpoint,
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let snapshot = EntryPropertiesTargetSnapshot(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: propertyID.rawValue),
            catalogVersion: "2.2.0",
            canonicalRevision: 0,
        )
        let request = EntryPropertiesPrepareRequest(
            snapshot: snapshot,
            intent: .init(change: .set(.text("after"))),
        )

        do {
            _ = try await client.prepare(request)
            XCTFail("mismatched proposal should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }
    }
}

private func mismatchedPropertyClient(response: PropertyChangeProposal) -> EntryCorePropertyClient {
    EntryCorePropertyClient(
        definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionReorder: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        assignmentList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        changePrepare: { _, _ in response },
        changeExecute: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        conditionQuery: { _, _ in throw EntryCoreClientError.daemonUnavailable },
    )
}

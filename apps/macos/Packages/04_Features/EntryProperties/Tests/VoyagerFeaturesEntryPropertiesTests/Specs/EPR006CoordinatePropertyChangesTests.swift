import ComposableArchitecture
@testable import VoyagerEntryCoreClient
@testable import VoyagerFeaturesEntryProperties
import XCTest

@MainActor
final class EPR006CoordinatePropertyChangesTests: XCTestCase {
    // MARK: - EPR-006-discover_property_change_capabilities

    /// EPR-006-discover_property_change_capabilities: catalog-first 순서와 authoritative capability를 확인한다.
    /// 조건 조회 capability를 mutation capability로 승격하지 않는 경계를 검증한다.
    /// - 검증 내용: catalog → assignment → capability 호출 순서와 unknown 보존
    /// - 사전 조건: 하나의 고정 target selection과 unknown mutation capability
    /// - 기대 결과: snapshot이 게시되고 changeValue capability는 unknown으로 유지됨
    func testDiscoveryReadsCatalogBeforeAssignmentsAndPreservesUnknownMutationCapability() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        let unknownReport = EntryPropertiesCapabilityReport(
            items: [.init(operation: .changeValue, capability: .unknown)],
            supportsMultipleTargets: false,
            catalogVersion: "2.2.0",
        )
        let store = TestStore(initialState: EntryPropertiesState(selection: fixture.selection)) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = EntryPropertiesClient(
                loadCatalog: { _ in
                    await recorder.record("catalog")
                    return fixture.catalog
                },
                loadAssignments: { _, _ in
                    await recorder.record("assignments")
                    return fixture.assignments
                },
                discoverCapabilities: { _ in
                    await recorder.record("capabilities")
                    return unknownReport
                },
                prepare: { _ in throw EntryPropertiesFailure.unavailable },
                execute: { _ in throw EntryPropertiesFailure.unavailable },
                readBack: { _ in throw EntryPropertiesFailure.unavailable },
            )
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
        }
        let discovery = EntryPropertiesDiscovery(snapshot: fixture.snapshot, capabilities: unknownReport)
        await store.receive(.init(kind: .discoveryCompleted(1, .success(discovery)))) {
            $0.activePhase = nil
            $0.targetSnapshot = fixture.snapshot
            $0.capabilityReport = unknownReport
            $0.status = .ready
            $0.lastOutcome = .capabilitiesDiscovered(unknownReport)
        }
        await store.receive(.init(kind: .outcome(.capabilitiesDiscovered(unknownReport))))

        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["catalog", "assignments", "capabilities"])
        XCTAssertEqual(store.state.capabilityReport?.capability(for: .changeValue), .unknown)
    }

    /// EPR-006-discover_property_change_capabilities: unresolved selection은 fail closed한다.
    /// authoritative discovery 실패 시 지원 가능성을 추론하지 않는지 검증한다.
    /// - 검증 내용: unavailable 결과와 mutation capability 미게시
    /// - 사전 조건: catalog 조회가 실패하는 selection
    /// - 기대 결과: rejected(unavailable), capabilityReport=nil
    func testDiscoveryFailureDoesNotFabricateCapability() async {
        let fixture = Fixture()
        let store = TestStore(initialState: EntryPropertiesState(selection: fixture.selection)) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = .unavailable
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
        XCTAssertNil(store.state.capabilityReport)
    }

    // MARK: - EPR-006-prepare_property_change

    /// EPR-006-prepare_property_change: 고정 snapshot과 before/after를 가진 immutable proposal을 준비한다.
    /// capability가 확인된 현재 revision에 대해서만 proposal을 게시하는지 검증한다.
    /// - 검증 내용: snapshot, differences, impact, validation, confirmation requirement
    /// - 사전 조건: changeValue 및 multi-target capability가 authoritative supported
    /// - 기대 결과: property_change_prepared outcome과 원본 snapshot 유지
    func testPreparePublishesImmutableProposalForCurrentSnapshot() async {
        let fixture = Fixture()
        var state = fixture.readyState
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(prepare: { _ in fixture.proposal })
        }

        await store.send(.prepare(fixture.intent)) {
            $0.activePhase = .preparing
            $0.status = .preparing
        }
        await store.receive(.init(kind: .prepareCompleted(0, .success(fixture.proposal)))) {
            $0.activePhase = nil
            $0.proposal = fixture.proposal
            $0.status = .prepared
            $0.lastOutcome = .propertyChangePrepared(fixture.proposal)
        }
        await store.receive(.init(kind: .outcome(.propertyChangePrepared(fixture.proposal))))
        state = store.state
        XCTAssertEqual(state.proposal?.snapshot, fixture.snapshot)
        XCTAssertEqual(state.proposal?.differences, fixture.proposal.differences)
    }

    /// EPR-006-prepare_property_change: 이전 generation의 completion은 현재 selection을 오염시키지 않는다.
    /// selection 교체 뒤 late proposal이 무시되는지 검증한다.
    /// - 검증 내용: generation freshness와 proposal publication 차단
    /// - 사전 조건: generation 0 prepare가 진행된 뒤 selection이 교체됨
    /// - 기대 결과: 이전 proposal은 게시되지 않고 새 selection이 유지됨
    func testLatePrepareCompletionCannotReplaceCurrentSelection() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/replacement")],
            propertyID: .init(rawValue: "property-b"),
        )
        var state = fixture.readyState
        state.generation = 1
        state.activePhase = .preparing
        state.status = .preparing
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.selectionChanged(replacement)) {
            $0.generation = 2
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.activePhase = nil
            $0.status = .idle
        }
        await store.send(.init(kind: .prepareCompleted(1, .success(fixture.proposal))))
        XCTAssertEqual(store.state.selection, replacement)
        XCTAssertNil(store.state.proposal)
    }

    /// EPR-006-execute_property_change: execute 중 selection 변경은 ambiguity를 지우지 않는다.
    /// - 검증 내용: 새 selection 초기화, ambiguous outcome, generation fencing
    /// - 사전 조건: 이전 selection의 confirmed proposal mutation이 실행 중임
    /// - 기대 결과: 새 selection에 stale completion이 반영되지 않고 ambiguity가 게시됨
    func testSelectionChangeDuringExecutionPreservesAmbiguityAndFencesCompletion() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.activePhase = .executing
        state.status = .executing
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        }

        await store.send(.selectionChanged(replacement)) {
            $0.generation = 1
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.appliedProposal = nil
            $0.pendingReadBack = fixture.proposal
            $0.canonicalResult = nil
            $0.activePhase = nil
            $0.status = .ambiguous
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
        await store.send(.init(kind: .executeCompleted(0, .success(.init(snapshot: fixture.snapshot)))))
        XCTAssertEqual(store.state.selection, replacement)
        XCTAssertEqual(store.state.status, .ambiguous)
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
        XCTAssertEqual(store.state.lastOutcome, .propertyChangeRejected(.ambiguousExecution))
    }

    // MARK: - EPR-006-execute_property_change

    /// EPR-006-execute_property_change: busy 거부는 진행 중 mutation을 해제하지 않는다.
    /// - 검증 내용: discovery/reconnect/execute 중복 요청의 phase·status·generation 보존
    /// - 사전 조건: confirmed proposal execute가 이미 진행 중임
    /// - 기대 결과: busy outcome만 게시되고 새 client operation은 시작되지 않음
    func testBusyRejectionPreservesExecutingMutation() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.activePhase = .executing
        state.status = .executing
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client()
        }

        await store.send(.discoverCapabilities) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.activePhase, .executing)
        XCTAssertEqual(store.state.status, .executing)
        XCTAssertEqual(store.state.generation, 0)

        for action in [EntryPropertiesAction.reconnect, .execute(confirmed: true)] {
            await store.send(action)
            await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
            XCTAssertEqual(store.state.activePhase, .executing)
            XCTAssertEqual(store.state.status, .executing)
            XCTAssertEqual(store.state.generation, 0)
        }
    }

    /// EPR-006-execute_property_change: ambiguous completion은 mutation 재시도 없이 보존한다.
    /// 전송 또는 cancellation ambiguity를 성공·실패로 추정하지 않는지 검증한다.
    /// - 검증 내용: ambiguous status와 proposal 보존
    /// - 사전 조건: current proposal의 execute effect가 active
    /// - 기대 결과: 자동 execute/read-back 없이 ambiguous outcome
    func testAmbiguousExecutionIsNotRetried() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .executing
        state.activePhase = .executing
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.init(kind: .executeCompleted(0, .failure(.ambiguousExecution)))) {
            $0.activePhase = nil
            $0.pendingReadBack = fixture.proposal
            $0.status = .ambiguous
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
        XCTAssertEqual(store.state.proposal, fixture.proposal)
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
        XCTAssertNil(store.state.canonicalResult)

        await store.send(.reconnect) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.status, .ambiguous)
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
    }

    /// EPR-006-execute_property_change: Entry Core 오류 의미를 lifecycle failure로 보존한다.
    /// - 검증 내용: deterministic server error와 post-write transport ambiguity mapping
    /// - 사전 조건: strict Entry Core client error taxonomy
    /// - 기대 결과: conflict/unsupported/authorization/validation과 ambiguous execute 구분
    func testEntryCoreErrorsMapToLifecycleSemantics() {
        XCTAssertEqual(mappedFailure(EntryCoreClientError.server(.conflict)), .conflict)
        XCTAssertEqual(mappedFailure(EntryCoreClientError.server(.unsupported)), .unsupported)
        XCTAssertEqual(mappedFailure(EntryCoreClientError.server(.permissionDenied)), .authorization)
        XCTAssertEqual(mappedFailure(EntryCoreClientError.server(.invalidRequest)), .validation)
        XCTAssertEqual(mappedFailure(EntryCoreClientError.daemonUnavailable), .unavailable)
        XCTAssertEqual(mappedExecutionFailure(EntryCoreClientError.localValidation), .validation)

        for error in [
            EntryCoreClientError.cancelled,
            .timedOut(.write),
            .timedOut(.read),
            .transport(.write),
            .transport(.read),
            .responseTooLarge,
            .malformedResponse,
            .protocolMismatch,
            .requestIDMismatch,
        ] {
            XCTAssertEqual(mappedExecutionFailure(error), .ambiguousExecution)
        }
        XCTAssertEqual(mappedExecutionFailure(EntryCoreClientError.transport(.connect)), .unavailable)
        XCTAssertEqual(mappedExecutionFailure(EntryCoreClientError.server(.conflict)), .conflict)
    }

    /// EPR-006-execute_property_change: trusted success 뒤 canonical read-back까지 완료한다.
    /// mutation과 정본 확인이 한 번씩 직렬 실행되는 happy path를 검증한다.
    /// - 검증 내용: applied → verified 전이와 execute/readBack 호출 횟수
    /// - 사전 조건: 확인된 current proposal과 authoritative supported capability
    /// - 기대 결과: 고정 snapshot의 canonical result가 property_change_verified로 게시됨
    func testTrustedExecuteReadsBackCanonicalResult() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .prepared
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                },
                readBack: { _ in
                    await recorder.record("readBack")
                    return fixture.canonicalResult
                },
            )
        }

        await store.send(.execute(confirmed: true)) {
            $0.activePhase = .executing
            $0.status = .executing
        }
        await store.receive(.init(kind: .executeCompleted(0, .success(.init(snapshot: fixture.snapshot))))) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
            $0.appliedProposal = fixture.proposal
            $0.status = .applied
            $0.lastOutcome = .propertyChangeApplied(fixture.snapshot)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeApplied(fixture.snapshot))))
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.canonicalResult = fixture.canonicalResult
            $0.targetSnapshot = fixture.verifiedSnapshot
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["execute", "readBack"])
    }

    /// EPR-006-prepare_property_change: 검증 완료 뒤 snapshot revision을 갱신한다.
    /// - 검증 내용: canonical read-back 성공 뒤 정본 assignment revision 보존
    /// - 사전 조건: current selection의 applied proposal과 성공한 read-back
    /// - 기대 결과: verified snapshot이 실행 후 revision을 보유함
    func testVerifiedReadBackRefreshesSnapshotRevisions() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.activePhase = .applied
        state.status = .applied
        state.readBackProposal = fixture.proposal
        state.appliedProposal = fixture.proposal
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.canonicalResult = fixture.canonicalResult
            $0.targetSnapshot = fixture.verifiedSnapshot
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertEqual(store.state.targetSnapshot, fixture.verifiedSnapshot)
    }

    /// EPR-006-read_back_property_change_result: proposal after와 다른 정본은 verified가 아니다.
    /// - 검증 내용: 누락·불일치·중복·stale revision canonical 결과의 fail-closed 전이
    /// - 사전 조건: trusted apply 뒤 고정 snapshot의 read-back 결과가 proposal과 다름
    /// - 기대 결과: applied-unverified를 유지하고 verified result를 게시하지 않음
    func testReadBackRequiresExactProposalValuesBeforeVerification() async {
        let fixture = Fixture()
        let target = fixture.selection.targets[0]
        let mismatches = [
            EntryPropertiesCanonicalResult(snapshot: fixture.snapshot, values: []),
            EntryPropertiesCanonicalResult(
                snapshot: fixture.snapshot,
                values: [.init(target: target, value: .text("different"), revision: 8)],
            ),
            EntryPropertiesCanonicalResult(
                snapshot: fixture.snapshot,
                values: fixture.selection.targets.map {
                    .init(target: $0, value: .text("after"), revision: 7)
                },
            ),
            EntryPropertiesCanonicalResult(
                snapshot: fixture.snapshot,
                values: fixture.selection.targets.map {
                    .init(target: $0, value: .text("after"), revision: 9)
                },
            ),
            EntryPropertiesCanonicalResult(
                snapshot: fixture.snapshot,
                values: [
                    .init(target: target, value: .text("after"), revision: 8),
                    .init(target: target, value: .text("after"), revision: 8),
                ],
            ),
        ]

        for canonicalResult in mismatches {
            var state = fixture.readyState
            state.activePhase = .applied
            state.status = .applied
            state.appliedProposal = fixture.proposal
            let store = TestStore(initialState: state) {
                EntryPropertiesFeature()
            }

            await store.send(.init(kind: .readBackCompleted(0, .success(canonicalResult)))) {
                $0.activePhase = nil
                $0.status = .appliedUnverified
                $0.lastOutcome = .propertyChangeAppliedUnverified(fixture.snapshot)
            }
            await store.receive(.init(kind: .outcome(.propertyChangeAppliedUnverified(fixture.snapshot))))
            XCTAssertNil(store.state.canonicalResult)
        }
    }

    // MARK: - EPR-006-read_back_property_change_result

    /// EPR-006-read_back_property_change_result: applied-unverified 재시도는 read-only다.
    /// mutation을 반복하지 않고 같은 고정 snapshot의 정본만 조회하는지 검증한다.
    /// - 검증 내용: readBack 1회, execute 0회, verified canonical result
    /// - 사전 조건: trusted apply 뒤 첫 정본 조회가 실패한 상태
    /// - 기대 결과: 동일 snapshot의 property_change_verified
    func testAppliedUnverifiedRetryPerformsReadBackOnly() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.status = .appliedUnverified
        state.appliedProposal = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                execute: { proposal in
                    await recorder.record("execute")
                    return .init(snapshot: proposal.snapshot)
                },
                readBack: { _ in
                    await recorder.record("readBack")
                    return fixture.canonicalResult
                },
            )
        }

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.canonicalResult = fixture.canonicalResult
            $0.targetSnapshot = fixture.verifiedSnapshot
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["readBack"])
    }
}

extension EPR006CoordinatePropertyChangesTests {
    /// EPR-006-discover_property_change_capabilities: 재탐색 시작은 이전 snapshot을 폐기한다.
    /// - 검증 내용: discovery 중 snapshot/capability 무효화와 실패 후 stale prepare 차단
    /// - 사전 조건: 기존 ready snapshot을 가진 상태에서 재탐색이 시작됨
    /// - 기대 결과: 실패한 refresh의 이전 정본으로 mutation proposal을 만들지 않음
    func testRediscoveryInvalidatesPreviousSnapshotBeforeFailure() async {
        let fixture = Fixture()
        let store = TestStore(initialState: fixture.readyState) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = .unavailable
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
        XCTAssertNil(store.state.targetSnapshot)
        XCTAssertNil(store.state.capabilityReport)

        await store.send(.prepare(fixture.intent)) {
            $0.status = .rejected(.stale)
            $0.lastOutcome = .propertyChangeRejected(.stale)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.stale))))
    }

    /// EPR-006-read_back_property_change_result: read-back 중 discovery/reconnect는 busy로 보존한다.
    /// - 검증 내용: applied phase·status·generation·proposal 보존
    /// - 사전 조건: trusted apply 뒤 canonical read-back effect가 진행 중임
    /// - 기대 결과: 재연결이나 capability discovery가 read-back을 취소하지 않고 busy outcome만 게시함
    func testBusyRejectionPreservesAppliedReadBack() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.appliedProposal = fixture.proposal
        state.activePhase = .applied
        state.status = .applied
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.discoverCapabilities) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.activePhase, .applied)
        XCTAssertEqual(store.state.status, .applied)
        XCTAssertEqual(store.state.generation, 0)
        XCTAssertEqual(store.state.appliedProposal, fixture.proposal)

        await store.send(.reconnect)
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.activePhase, .applied)
        XCTAssertEqual(store.state.status, .applied)
        XCTAssertEqual(store.state.generation, 0)
        XCTAssertEqual(store.state.appliedProposal, fixture.proposal)
    }

    /// EPR-006-execute_property_change: 취소 시 lifecycle outcome을 caller에 발행한다.
    /// - 검증 내용: execute cancellation의 ambiguity와 read-back cancellation의 applied-unverified
    /// - 사전 조건: 각 phase의 effect가 진행 중임
    /// - 기대 결과: 취소 effect와 phase별 public outcome이 함께 게시됨
    func testCancellationPublishesPhaseSpecificOutcome() async {
        let fixture = Fixture()

        var executingState = fixture.readyState
        executingState.proposal = fixture.proposal
        executingState.activePhase = .executing
        executingState.status = .executing
        let executingStore = TestStore(initialState: executingState) { EntryPropertiesFeature() }

        await executingStore.send(.cancel) {
            $0.generation = 1
            $0.pendingReadBack = fixture.proposal
            $0.activePhase = nil
            $0.status = .ambiguous
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await executingStore.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))

        var appliedState = fixture.readyState
        appliedState.appliedProposal = fixture.proposal
        appliedState.activePhase = .applied
        appliedState.status = .applied
        let appliedStore = TestStore(initialState: appliedState) { EntryPropertiesFeature() }

        await appliedStore.send(.cancel) {
            $0.generation = 1
            $0.activePhase = nil
            $0.status = .appliedUnverified
            $0.lastOutcome = .propertyChangeAppliedUnverified(fixture.snapshot)
        }
        await appliedStore.receive(
            .init(kind: .outcome(.propertyChangeAppliedUnverified(fixture.snapshot))),
        )
    }

    /// EPR-006-execute_property_change: 취소할 active effect가 없으면 recovery 상태를 유지한다.
    /// - 검증 내용: applied-unverified/ambiguous 상태에서 cancel의 status 보존
    /// - 사전 조건: execute ambiguity 또는 read-back 실패가 이미 완료됨 (activePhase == nil)
    /// - 기대 결과: status가 idle로 덮이지 않아 read-only retry 경계와 busy guard가 유지됨
    func testCancelWithoutActiveEffectPreservesRecoveryStatus() async {
        let fixture = Fixture()

        var unverifiedState = fixture.readyState
        unverifiedState.appliedProposal = fixture.proposal
        unverifiedState.status = .appliedUnverified
        let unverifiedStore = TestStore(initialState: unverifiedState) { EntryPropertiesFeature() }

        await unverifiedStore.send(.cancel) {
            $0.generation = 1
        }
        XCTAssertEqual(unverifiedStore.state.status, .appliedUnverified)
        XCTAssertEqual(unverifiedStore.state.appliedProposal, fixture.proposal)

        var ambiguousState = fixture.readyState
        ambiguousState.proposal = fixture.proposal
        ambiguousState.status = .ambiguous
        let ambiguousStore = TestStore(initialState: ambiguousState) { EntryPropertiesFeature() }

        await ambiguousStore.send(.cancel) {
            $0.generation = 1
        }
        XCTAssertEqual(ambiguousStore.state.status, .ambiguous)
        XCTAssertEqual(ambiguousStore.state.proposal, fixture.proposal)
    }

    // MARK: - mutation 응답·request 계약 강화 (EPR006CoordinatePropertyChangesTests+ReviewHardening.swift)

    /// EPR-006-execute_property_change: 확인이 필요한 proposal은 확인 전 로컬에서 거부한다.
    /// 정본 write dependency를 호출하지 않는 preflight를 검증한다.
    /// - 검증 내용: confirmationRequired outcome과 execute 호출 0회
    /// - 사전 조건: requiresConfirmation=true인 current proposal
    /// - 기대 결과: 확인 전 proposal을 보존하고 확인 후 실행을 허용함
    func testExecuteRejectsUnconfirmedProposalBeforeMutation() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.status = .prepared
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(execute: { _ in
                await recorder.record("execute")
                throw EntryPropertiesFailure.unavailable
            })
        }

        await store.send(.execute(confirmed: false)) {
            $0.lastOutcome = .propertyChangeRejected(.confirmationRequired)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.confirmationRequired))))
        XCTAssertEqual(store.state.status, .prepared)
        XCTAssertEqual(store.state.proposal, fixture.proposal)
        let initialRecordedOperations = await recorder.values()
        XCTAssertEqual(initialRecordedOperations, [])

        await store.send(.execute(confirmed: true)) {
            $0.activePhase = .executing
            $0.status = .executing
        }
        await store.receive(.init(kind: .executeCompleted(0, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["execute"])
    }

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

    /// EPR-006-read_back_property_change_result: applied-unverified 상태에서는 재탐색을 시작하지 않는다.
    /// - 검증 내용: discover/reconnect busy rejection과 applied proposal/read-back 상태 보존
    /// - 사전 조건: trusted apply 뒤 canonical read-back이 실패해 현재 proposal이 applied-unverified로 남음
    /// - 기대 결과: 재탐색 effect를 시작하지 않고 read-only retry 경로를 보존함
    func testAppliedUnverifiedBlocksRediscovery() async {
        let fixture = Fixture()
        for action in [EntryPropertiesAction.discoverCapabilities, .reconnect] {
            var state = fixture.readyState
            state.status = .appliedUnverified
            state.appliedProposal = fixture.proposal
            let store = TestStore(initialState: state) {
                EntryPropertiesFeature()
            } withDependencies: {
                $0.entryPropertiesClient = fixture.client()
            }

            await store.send(action) {
                $0.lastOutcome = .propertyChangeRejected(.busy)
            }
            await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
            XCTAssertEqual(store.state.status, .appliedUnverified)
            XCTAssertEqual(store.state.appliedProposal, fixture.proposal)
            XCTAssertEqual(store.state.generation, 0)
        }
    }

    /// EPR-006-read_back_property_change_result: selection 변경 후에도 applied-unverified proposal을 보존한다.
    /// - 검증 내용: 완료된 read-back 실패의 pending 보존과 기존 outcome 재게시
    /// - 사전 조건: applied-unverified 상태에 현재 selection용 applied proposal이 있음
    /// - 기대 결과: 새 selection은 초기화되고 이전 proposal은 read-only retry 대상으로 남음
    func testSelectionChangeAfterAppliedUnverifiedPreservesPendingOutcome() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.status = .appliedUnverified
        state.appliedProposal = fixture.proposal
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
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
        XCTAssertEqual(store.state.status, .idle)
    }

    /// EPR-006-read_back_property_change_result: 완료된 ambiguous proposal도 selection 변경 뒤 pending read-back으로 보존한다.
    /// - 검증 내용: ambiguous proposal의 pending 보존과 ambiguity outcome 재게시
    /// - 사전 조건: execute completion이 ambiguous로 종료되어 proposal만 남아 있음
    /// - 기대 결과: 새 selection은 idle이지만 이전 snapshot은 read-only retry 대상으로 남음
    func testSelectionChangeAfterAmbiguousExecutionPreservesPendingReadBack() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.status = .ambiguous
        state.proposal = fixture.proposal
        let store = TestStore(initialState: state) { EntryPropertiesFeature() }

        await store.send(.selectionChanged(replacement)) {
            $0.generation = 1
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.appliedProposal = nil
            $0.pendingReadBack = fixture.proposal
            $0.canonicalResult = nil
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
        XCTAssertEqual(store.state.status, .idle)
        XCTAssertNil(store.state.proposal)
    }

    /// EPR-006-prepare_property_change: ambiguous 상태에서는 새 mutation을 시작하지 않는다.
    /// - 검증 내용: ambiguity 보존 중 prepare busy rejection과 dependency 호출 0회
    /// - 사전 조건: execute 전송 결과가 ambiguous이고 기존 proposal이 남아 있음
    /// - 기대 결과: reconnect/read-back recovery 전까지 새 prepare를 시작하지 않음
    func testAmbiguousBlocksNewPrepare() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.status = .ambiguous
        state.proposal = fixture.proposal
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
        XCTAssertEqual(store.state.status, .ambiguous)
        XCTAssertEqual(store.state.proposal, fixture.proposal)
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

    /// EPR-006-prepare_property_change: Core before는 고정 snapshot의 assignment 계약과
    /// 일치해야 한다.
    /// - 검증 내용: before의 value type/cardinality/revision과 암시적 unset 불일치 거절
    /// - 사전 조건: target/property identity는 맞지만 snapshot 계약을 위반하는 Core proposal
    /// - 기대 결과: 모순된 before를 semantic difference로 변환하지 않고 validation으로 fail closed
    func testPrepareRejectsBeforeViolatingSnapshotContract() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let target = try PropertyTarget(localPath: "/a")
        let snapshot = EntryPropertiesTargetSnapshot(
            targets: [.init(localPath: target.localPath)],
            propertyID: .init(rawValue: propertyID.rawValue),
            catalogVersion: "2.2.0",
            canonicalRevision: 7,
        )
        let request = EntryPropertiesPrepareRequest(
            snapshot: snapshot,
            intent: .init(change: .set(.text("after"))),
        )
        let desired = PropertyDesiredState.value(.text, .one, .text("after"))
        for (name, before) in invalidPreparedBefores(propertyID: propertyID, entryID: entryID) {
            let response = PropertyChangeProposal(
                changes: [
                    PropertyPreparedChange(
                        target: target,
                        propertyID: propertyID,
                        entryID: entryID,
                        before: before,
                        after: desired,
                    ),
                ],
                requiresConfirmation: true,
            )
            let client = try EntryPropertiesClientFactory.live(
                propertyClient: mismatchedPropertyClient(response: response),
                endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
                capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
            )

            do {
                _ = try await client.prepare(request)
                XCTFail("snapshot-violating before (\(name)) should be rejected")
            } catch {
                XCTAssertEqual(error as? EntryPropertiesFailure, .validation, name)
            }
        }
    }

    /// EPR-006-prepare_property_change: snapshot과 일치하는 durable before는
    /// semantic difference로 변환할 수 있다.
    /// - 검증 내용: snapshot의 value type/cardinality/revision과 일치하는 before 허용
    /// - 기대 결과: before/after를 보존한 proposal 생성
    func testPrepareAcceptsBeforeMatchingSnapshotContract() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let target = try PropertyTarget(localPath: "/a")
        let snapshot = EntryPropertiesTargetSnapshot(
            targets: [.init(localPath: target.localPath)],
            propertyID: .init(rawValue: propertyID.rawValue),
            catalogVersion: "2.2.0",
            canonicalRevision: 7,
        )
        let response = PropertyChangeProposal(
            changes: [
                PropertyPreparedChange(
                    target: target,
                    propertyID: propertyID,
                    entryID: entryID,
                    before: PropertyAssignment(
                        propertyID: propertyID,
                        entryID: entryID,
                        valueType: .text,
                        cardinality: .one,
                        state: .value,
                        revision: 7,
                        value: .text("before"),
                    ),
                    after: .value(.text, .one, .text("after")),
                ),
            ],
            requiresConfirmation: true,
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: mismatchedPropertyClient(response: response),
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )

        let proposal = try await client.prepare(
            .init(snapshot: snapshot, intent: .init(change: .set(.text("after")))),
        )
        XCTAssertEqual(
            proposal.differences,
            [.init(target: .init(localPath: "/a", entryID: entryID), before: .text("before"), after: .text("after"))],
        )
    }

    /// EPR-006-read_back_property_change_result: assignment은 catalog value contract와 대조된다.
    /// - 검증 내용: definition-derived catalog와 다른 value type assignment 거절
    /// - 사전 조건: text/one snapshot 계약에 number/one assignment를 반환하는 Core stub
    /// - 기대 결과: 모순된 canonical baseline을 만들지 않고 validation으로 fail closed
    func testReadBackRejectsAssignmentViolatingCatalogContract() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let mismatched = PropertyAssignment(
            propertyID: propertyID,
            entryID: entryID,
            valueType: .number,
            cardinality: .one,
            state: .value,
            revision: 1,
            value: .number("42"),
        )
        let propertyClient = contractViolatingAssignmentClient(
            page: PropertyAssignmentPage(assignments: [mismatched], nextPageToken: nil, hasMore: false),
        )
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

        do {
            _ = try await client.readBack(.init(snapshot: snapshot))
            XCTFail("catalog-violating assignment should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }
    }

    /// Ambiguous execute는 동일 proposal로 read-back만 재시도하고 mutation을
    /// 재전송하지 않는다.
    func testAmbiguousRetryUsesReadBackOnly() async {
        let recorder = OperationRecorder()
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.pendingReadBack = fixture.proposal
        state.status = .ambiguous
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                execute: { _ in
                    await recorder.record("execute")
                    return .init(snapshot: fixture.snapshot)
                },
                readBack: { _ in
                    await recorder.record("readBack")
                    return fixture.canonicalResult
                },
            )
        }

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.appliedProposal = fixture.proposal
            $0.canonicalResult = fixture.canonicalResult
            $0.targetSnapshot = fixture.verifiedSnapshot
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["readBack"])
    }

    /// read-back이 동일 path를 다른 canonical entry로 해석하면 stable identity
    /// conflict로 닫고 값을 채택하지 않는다.
    func testReadBackRejectsTargetIdentityDrift() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let expectedEntryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let replacementEntryID = try EntryCoreEntryID(rawValue: "ent:UCqcybbCfAKpfjndstZqrNVefCWIjYqySFylQRoTDGw")
        let assignment = PropertyAssignment(
            propertyID: propertyID,
            entryID: replacementEntryID,
            valueType: .text,
            cardinality: .one,
            state: .value,
            revision: 1,
            value: .text("replacement"),
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: contractViolatingAssignmentClient(
                page: PropertyAssignmentPage(assignments: [assignment], nextPageToken: nil, hasMore: false),
            ),
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let snapshot = EntryPropertiesTargetSnapshot(
            targets: [.init(localPath: "/a", entryID: expectedEntryID)],
            propertyID: .init(rawValue: propertyID.rawValue),
            catalogVersion: "2.2.0",
            canonicalRevision: 0,
        )

        do {
            _ = try await client.readBack(.init(snapshot: snapshot))
            XCTFail("target identity drift should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .conflict)
        }
    }

    /// EPR-006-prepare_property_change / EPR-006-execute_property_change: 전송 전
    /// request model 검증 실패를 transport 장애나 실행 ambiguity로 분류하지 않는다.
    /// - 검증 내용: malformed decimal·4097바이트 text의 prepare/execute 요청 0회
    /// - 사전 조건: valid snapshot과 전송 전 검증을 실패시키는 사용자 입력
    /// - 기대 결과: 두 API 모두 validation을 반환하고 Core mutation 경계를 호출하지 않음
    func testRequestAssemblyValidationDoesNotBecomeTransportFailure() async throws {
        let recorder = OperationRecorder()
        let endpoint = try EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock")
        let client = EntryPropertiesClientFactory.live(
            propertyClient: requestAssemblyValidationClient(recorder: recorder),
            endpoint: endpoint,
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let snapshot = EntryPropertiesTargetSnapshot(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: "00000000-0000-0000-8000-000000000001"),
            catalogVersion: "2.2.0",
            canonicalRevision: 0,
        )
        let intents = [
            EntryPropertiesChangeIntent(change: .set(.text(String(repeating: "x", count: 4097)))),
            EntryPropertiesChangeIntent(change: .set(.number("1."))),
        ]

        for intent in intents {
            do {
                _ = try await client.prepare(.init(snapshot: snapshot, intent: intent))
                XCTFail("request assembly should reject invalid intent")
            } catch {
                XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
            }

            let proposal = EntryPropertiesProposal(
                snapshot: snapshot,
                intent: intent,
                differences: [],
                affectedTargetCount: 1,
                validation: .init(isValid: true),
                requiresConfirmation: false,
            )
            do {
                _ = try await client.execute(proposal)
                XCTFail("request assembly should reject invalid intent")
            } catch {
                XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
            }
        }
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, [])
    }

    // MARK: - identity 보강·취소 복구 (EPR006CoordinatePropertyChangesTests+IdentityRecovery.swift)

    /// EPR-006-execute_property_change: 실행 중 취소도 전송 경계 ambiguity로 다룬다.
    /// - 검증 내용: cancel 이후 proposal의 pending read-back 보존과 read-only retry 복구
    /// - 사전 조건: execute effect 진행 중 .cancel 수신
    /// - 기대 결과: ambiguous 상태에서 retryReadBack로 적용 여부를 확인할 수 있음
    func testCancelDuringExecutePreservesPendingReadBackForRetry() async {
        let fixture = Fixture()
        var state = fixture.readyState
        state.proposal = fixture.proposal
        state.activePhase = .executing
        state.status = .executing
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                readBack: { _ in fixture.canonicalResult },
            )
        }

        await store.send(.cancel) {
            $0.generation = 1
            $0.pendingReadBack = fixture.proposal
            $0.activePhase = nil
            $0.status = .ambiguous
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(1, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.appliedProposal = fixture.proposal
            $0.canonicalResult = fixture.canonicalResult
            $0.targetSnapshot = fixture.verifiedSnapshot
            $0.status = .verified
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertEqual(store.state.status, .verified)
        XCTAssertNil(store.state.pendingReadBack)
    }

    /// EPR-006-read_back_property_change_result: 반복 selection 변경에도 pending 복구 상태는 유지된다.
    /// - 검증 내용: 두 번째 selection 변경에서 pendingReadBack과 복구 outcome 보존
    /// - 사전 조건: 첫 selection 변경이 ambiguous proposal을 pendingReadBack으로 옮긴 상태
    /// - 기대 결과: 공개 상태가 복구 사유를 유지하고 prepare는 busy로 거절됨
    func testRepeatedSelectionChangePreservesPendingRecoveryOutcome() async {
        let fixture = Fixture()
        let firstSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/first")],
            propertyID: fixture.selection.propertyID,
        )
        let secondSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/second")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.status = .ambiguous
        state.proposal = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        }

        await store.send(.selectionChanged(firstSelection)) {
            $0.generation = 1
            $0.selection = firstSelection
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.appliedProposal = nil
            $0.pendingReadBack = fixture.proposal
            $0.canonicalResult = nil
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))

        await store.send(.selectionChanged(secondSelection)) {
            $0.generation = 2
            $0.selection = secondSelection
        }
        XCTAssertEqual(store.state.lastOutcome, .propertyChangeRejected(.ambiguousExecution))
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)

        await store.send(.prepare(fixture.intent)) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)
    }

    /// EPR-006-discover_property_change_capabilities: pending recovery 중 discovery는 차단된다.
    /// - 검증 내용: pendingReadBack 잔존 시 discover busy 거절과 복구 후 재개
    /// - 사전 조건: selection 변경으로 ambiguous proposal이 pendingReadBack으로 이동
    /// - 기대 결과: read-only retry로 복구되기 전까지 discovery가 시작되지 않음
    func testPendingRecoveryBlocksDiscoveryUntilResolved() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.status = .ambiguous
        state.proposal = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = fixture.client(
                readBack: { _ in fixture.canonicalResult },
            )
        }

        await moveAmbiguousProposalToPendingReadBack(store, replacement: replacement, fixture: fixture)

        await store.send(.discoverCapabilities) {
            $0.lastOutcome = .propertyChangeRejected(.busy)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.busy))))
        XCTAssertEqual(store.state.pendingReadBack, fixture.proposal)

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(1, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertNil(store.state.pendingReadBack)

        await store.send(.discoverCapabilities) {
            $0.generation = 2
            $0.activePhase = .discovering
            $0.status = .discovering
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
        }
        await store.receive(.init(kind: .discoveryCompleted(2, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
    }

    /// EPR-006-prepare_property_change: identity 보강 전 snapshot의 unset target
    /// revision은 local path로 대응한다.
    /// - 검증 내용: 일부 target만 assignment를 가진 변경에서 prepare before == nil 수용
    /// - 사전 조건: /a는 revision 3의 durable assignment, /b는 암시적 unset(discovery)
    /// - 기대 결과: canonicalRevision fallback 대신 target별 revision으로 정상 proposal 생성
    func testPrepareMatchesUnsetTargetRevisionByLocalPath() async throws {
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: prepareStubClient(response: mixedIdentityPreparedResponse()),
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )

        let proposal = try await client.prepare(
            .init(snapshot: mixedIdentitySnapshot(), intent: .init(change: .set(.text("after")))),
        )
        XCTAssertEqual(proposal.differences, try mixedIdentityDifferences())
    }

    /// EPR-006-read_back_property_change_result: 이전 selection 검증 성공은 ambiguous 대기를 푼다.
    /// - 검증 내용: currentSelection == false 성공 분기의 status .idle 복원과 discovery 재개
    /// - 사전 조건: 실행 취소로 .ambiguous + pendingReadBack이 남은 뒤 selection이 변경됨
    /// - 기대 결과: pending 제거와 함께 현재 selection이 idle로 복원되어 discovery가 다시 가능
    func testOldSelectionVerificationResolvesAmbiguousWait() async {
        let fixture = Fixture()
        let replacement = EntryPropertiesSelection(
            targets: [.init(localPath: "/tmp/replacement")],
            propertyID: fixture.selection.propertyID,
        )
        var state = fixture.readyState
        state.selection = replacement
        state.status = .ambiguous
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
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertEqual(store.state.status, .idle)
        XCTAssertNil(store.state.pendingReadBack)

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.unavailable)))) {
            $0.activePhase = nil
            $0.status = .rejected(.unavailable)
            $0.lastOutcome = .propertyChangeRejected(.unavailable)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.unavailable))))
    }

    /// EPR-006-read_back_property_change_result: 같은 local path에서 entry가
    /// 교체되면 이전 proposal의 검증 결과는 현재 selection의 verified가 되지 않는다.
    /// - 검증 내용: entry 교체 시 current-selection 분기 미채택과 pending 정리
    /// - 사전 조건: 동일 경로에 다른 entryID를 가진 selection과 이전 proposal pending
    /// - 기대 결과: canonical result를 채택하지 않고 idle로 복원해 재탐색을 유도함
    func testReadBackWithReplacedEntryDoesNotAdoptVerifiedResult() async throws {
        let fixture = try replacedEntryFixture()
        var state = EntryPropertiesState(selection: fixture.selection)
        state.pendingReadBack = fixture.proposal
        let store = TestStore(initialState: state) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = Fixture().client(readBack: { _ in fixture.canonicalResult })
        }

        await store.send(.retryReadBack) {
            $0.activePhase = .applied
            $0.readBackProposal = fixture.proposal
        }
        await store.receive(.init(kind: .readBackCompleted(0, .success(fixture.canonicalResult)))) {
            $0.activePhase = nil
            $0.pendingReadBack = nil
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeVerified(fixture.canonicalResult)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeVerified(fixture.canonicalResult))))
        XCTAssertEqual(store.state.status, .idle)
        XCTAssertNil(store.state.canonicalResult)
        XCTAssertNil(store.state.appliedProposal)
        XCTAssertNil(store.state.pendingReadBack)
    }

    /// ambiguous proposal을 selection 변경으로 pendingReadBack으로 옮기는 첫 단계다.
    private func moveAmbiguousProposalToPendingReadBack(
        _ store: TestStore<EntryPropertiesState, EntryPropertiesAction>,
        replacement: EntryPropertiesSelection,
        fixture: Fixture,
    ) async {
        await store.send(.selectionChanged(replacement)) {
            $0.generation = 1
            $0.selection = replacement
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.appliedProposal = nil
            $0.pendingReadBack = fixture.proposal
            $0.canonicalResult = nil
            $0.activePhase = nil
            $0.readBackProposal = nil
            $0.status = .idle
            $0.lastOutcome = .propertyChangeRejected(.ambiguousExecution)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.ambiguousExecution))))
    }

    // MARK: - 페이지네이션 계약 (EPR006CoordinatePropertyChangesTests+PaginationContract.swift)

    /// EPR-006-discover_property_change_capabilities: catalog 로드는 두 번째 페이지를 받지 않는다.
    /// - 검증 내용: hasMore 응답의 protocolMismatch 거절과 transport 호출 1회 종료
    /// - 사전 조건: 빈 definition 페이지에 hasMore를 반환하는 Core stub
    /// - 기대 결과: capability discovery가 토큰 추적 없이 즉시 실패로 종료됨
    func testLoadCatalogRejectsSecondPageUnderSingleIDFilter() async throws {
        let recorder = OperationRecorder()
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in
                await recorder.record("definitionList")
                return PropertyDefinitionPage(definitions: [], nextPageToken: "token", hasMore: true)
            },
            assignmentList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let selection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: propertyID.rawValue),
        )

        do {
            _ = try await client.loadCatalog(selection)
            XCTFail("second page under single-ID filter should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["definitionList"])
    }

    /// EPR-006-discover_property_change_capabilities: assignment 로드는 두 번째 페이지를 받지 않는다.
    /// - 검증 내용: 단일 target × ID 요청의 hasMore 거절과 transport 호출 1회 종료
    /// - 사전 조건: 빈 assignment 페이지에 hasMore를 반환하는 Core stub
    /// - 기대 결과: assignment 로드가 토큰 추적 없이 즉시 실패로 종료됨
    func testLoadAssignmentsRejectsSecondPageUnderSingleTargetFilter() async throws {
        let recorder = OperationRecorder()
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
            assignmentList: { _, _ in
                await recorder.record("assignmentList")
                return PropertyAssignmentPage(assignments: [], nextPageToken: "token", hasMore: true)
            },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let selection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: propertyID.rawValue),
        )
        let catalog = EntryPropertiesCatalog(version: "2.2.0")

        do {
            _ = try await client.loadAssignments(selection, catalog)
            XCTFail("second page under single-target filter should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        let recordedOperations = await recorder.values()
        XCTAssertEqual(recordedOperations, ["assignmentList"])
    }

    /// EPR-006-discover_property_change_capabilities: discovery 조립의 전송 전
    /// 실패는 caller 입력 결함이므로 validation으로 분류된다.
    /// - 검증 내용: malformed property ID·local path의 .validation 변환
    /// - 사전 조건: wire 생성자가 거절하는 공개 selection 값
    /// - 기대 결과: unavailable(복구 대상) 대신 validation(caller 결함)으로 fail closed
    func testDiscoveryClassifiesMalformedSelectionAsValidation() async throws {
        let propertyClient = paginatingPropertyClient(
            definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
            assignmentList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        )
        let client = try EntryPropertiesClientFactory.live(
            propertyClient: propertyClient,
            endpoint: EntryCoreEndpoint(path: "/tmp/entry-properties-review.sock"),
            capabilityDiscovery: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let catalog = EntryPropertiesCatalog(version: "2.2.0")

        let badIDSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "/a")],
            propertyID: .init(rawValue: "not-a-uuid"),
        )
        do {
            _ = try await client.loadCatalog(badIDSelection)
            XCTFail("malformed property ID should be rejected as validation")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }

        let badPathSelection = EntryPropertiesSelection(
            targets: [.init(localPath: "")],
            propertyID: .init(rawValue: "00000000-0000-0000-8000-000000000001"),
        )
        do {
            _ = try await client.loadAssignments(badPathSelection, catalog)
            XCTFail("malformed local path should be rejected as validation")
        } catch {
            XCTAssertEqual(error as? EntryPropertiesFailure, .validation)
        }
    }

    /// EPR-006-discover_property_change_capabilities: catalog과 capability의
    /// catalog version이 모두 있으면 일치해야 한다.
    /// - 검증 내용: version 불일치의 stale discovery 실패
    /// - 사전 조건: catalog 2.2.0에 3.0.0 capability를 반환하는 provider
    /// - 기대 결과: 서로 다른 계약을 한 snapshot으로 묶지 않고 discovery 실패
    func testDiscoveryRejectsCapabilityCatalogVersionMismatch() async {
        let client = EntryPropertiesClient(
            loadCatalog: { _ in EntryPropertiesCatalog(version: "2.2.0") },
            loadAssignments: { selection, _ in
                EntryPropertiesAssignments(
                    canonicalRevision: 0,
                    values: selection.targets.map { .init(target: $0, value: .unset, revision: 0) },
                )
            },
            discoverCapabilities: { _ in
                EntryPropertiesCapabilityReport(
                    items: [.init(operation: .changeValue, capability: .supported)],
                    supportsMultipleTargets: true,
                    catalogVersion: "3.0.0",
                )
            },
            prepare: { _ in throw EntryPropertiesFailure.unavailable },
            execute: { _ in throw EntryPropertiesFailure.unavailable },
            readBack: { _ in throw EntryPropertiesFailure.unavailable },
        )
        let fixture = Fixture()
        let store = TestStore(initialState: fixture.readyState) {
            EntryPropertiesFeature()
        } withDependencies: {
            $0.entryPropertiesClient = client
        }

        await store.send(.discoverCapabilities) {
            $0.generation = 1
            $0.activePhase = .discovering
            $0.status = .discovering
            $0.capabilityReport = nil
            $0.targetSnapshot = nil
            $0.proposal = nil
            $0.canonicalResult = nil
        }
        await store.receive(.init(kind: .discoveryCompleted(1, .failure(.stale)))) {
            $0.activePhase = nil
            $0.status = .rejected(.stale)
            $0.lastOutcome = .propertyChangeRejected(.stale)
        }
        await store.receive(.init(kind: .outcome(.propertyChangeRejected(.stale))))
    }
}

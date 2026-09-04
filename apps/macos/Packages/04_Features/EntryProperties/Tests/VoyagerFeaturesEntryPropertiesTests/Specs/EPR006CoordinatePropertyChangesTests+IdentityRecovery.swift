import ComposableArchitecture
@testable import VoyagerEntryCoreClient
@testable import VoyagerFeaturesEntryProperties
import XCTest

/// identity 보강과 취소 경계의 recovery 계약을 검증한다.
@MainActor
extension EPR006CoordinatePropertyChangesTests {
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
}

private struct ReplacedEntryFixture {
    let selection: EntryPropertiesSelection
    let proposal: EntryPropertiesProposal
    let canonicalResult: EntryPropertiesCanonicalResult
}

/// /a의 entry가 교체된 selection과 이전 identity의 proposal·검증 결과다.
private func replacedEntryFixture() throws -> ReplacedEntryFixture {
    let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
    let oldEntryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    let newEntryID = try EntryCoreEntryID(rawValue: "ent:UCqcybbCfAKpfjndstZqrNVefCWIjYqySFylQRoTDGw")
    let oldSnapshot = EntryPropertiesTargetSnapshot(
        reconcilingTargets: [.init(localPath: "/a", entryID: oldEntryID)],
        propertyID: .init(rawValue: propertyID.rawValue),
        catalogVersion: "2.2.0",
        canonicalRevision: 5,
        definitionRevision: 1,
        valueKind: .text,
        cardinality: .one,
        assignmentRevisions: [.init(target: .init(localPath: "/a", entryID: oldEntryID), revision: 5)],
    )
    let proposal = EntryPropertiesProposal(
        snapshot: oldSnapshot,
        intent: .init(change: .set(.text("after"))),
        differences: [
            .init(target: .init(localPath: "/a", entryID: oldEntryID), before: .unset, after: .text("after")),
        ],
        affectedTargetCount: 1,
        validation: .init(isValid: true),
        requiresConfirmation: false,
    )
    let canonicalResult = EntryPropertiesCanonicalResult(
        snapshot: oldSnapshot,
        values: [.init(target: .init(localPath: "/a", entryID: oldEntryID), value: .text("after"), revision: 6)],
    )
    return ReplacedEntryFixture(
        selection: EntryPropertiesSelection(
            targets: [.init(localPath: "/a", entryID: newEntryID)],
            propertyID: .init(rawValue: propertyID.rawValue),
        ),
        proposal: proposal,
        canonicalResult: canonicalResult,
    )
}

/// discovery 시점의 혼합 identity snapshot: /a는 assignment가 있고 /b는 암시적 unset이다.
private func mixedIdentitySnapshot() throws -> EntryPropertiesTargetSnapshot {
    let assignedEntryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    return EntryPropertiesTargetSnapshot(
        reconcilingTargets: [
            .init(localPath: "/a", entryID: assignedEntryID),
            .init(localPath: "/b"),
        ],
        propertyID: .init(rawValue: "00000000-0000-0000-8000-000000000001"),
        catalogVersion: "2.2.0",
        canonicalRevision: 3,
        definitionRevision: 1,
        valueKind: .text,
        cardinality: .one,
        assignmentRevisions: [
            .init(target: .init(localPath: "/a", entryID: assignedEntryID), revision: 3),
            .init(target: .init(localPath: "/b"), revision: 0),
        ],
    )
}

/// prepare가 identity를 보강한 응답: /b는 unset이던 target으로 before == nil을 반환한다.
private func mixedIdentityPreparedResponse() throws -> PropertyChangeProposal {
    let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
    let assignedEntryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    let unsetEntryID = try EntryCoreEntryID(rawValue: "ent:UCqcybbCfAKpfjndstZqrNVefCWIjYqySFylQRoTDGw")
    let desired = PropertyDesiredState.value(.text, .one, .text("after"))
    return try PropertyChangeProposal(
        changes: [
            PropertyPreparedChange(
                target: PropertyTarget(localPath: "/a"),
                propertyID: propertyID,
                entryID: assignedEntryID,
                before: PropertyAssignment(
                    propertyID: propertyID,
                    entryID: assignedEntryID,
                    valueType: .text,
                    cardinality: .one,
                    state: .value,
                    revision: 3,
                    value: .text("before"),
                ),
                after: desired,
            ),
            PropertyPreparedChange(
                target: PropertyTarget(localPath: "/b"),
                propertyID: propertyID,
                entryID: unsetEntryID,
                before: nil,
                after: desired,
            ),
        ],
        requiresConfirmation: true,
    )
}

/// prepare 통과 시 기대되는 semantic differences다.
private func mixedIdentityDifferences() throws -> [EntryPropertiesDifference] {
    let assignedEntryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    let unsetEntryID = try EntryCoreEntryID(rawValue: "ent:UCqcybbCfAKpfjndstZqrNVefCWIjYqySFylQRoTDGw")
    return [
        .init(
            target: .init(localPath: "/a", entryID: assignedEntryID),
            before: .text("before"),
            after: .text("after"),
        ),
        .init(
            target: .init(localPath: "/b", entryID: unsetEntryID),
            before: .unset,
            after: .text("after"),
        ),
    ]
}

private func prepareStubClient(response: PropertyChangeProposal) -> EntryCorePropertyClient {
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

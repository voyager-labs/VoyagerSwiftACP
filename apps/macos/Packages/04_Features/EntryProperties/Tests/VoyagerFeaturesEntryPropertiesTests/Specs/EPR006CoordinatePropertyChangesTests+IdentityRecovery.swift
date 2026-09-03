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

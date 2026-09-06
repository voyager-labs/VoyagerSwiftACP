import ComposableArchitecture
import Foundation
@testable import VoyagerEntryCoreClient
@testable import VoyagerFeaturesEntryProperties
import XCTest

// EPR-006 spec 테스트에서 재사용하는 fixture·stub·검증 helper다. Specs/에는
// 오너 스위트만 두고 helper는 Support/에 둔다(단일 owner suite 계약).

func invalidPreparedBefores(
    propertyID: PropertyID,
    entryID: EntryCoreEntryID,
) -> [(String, PropertyAssignment?)] {
    [
        (
            "value type",
            PropertyAssignment(
                propertyID: propertyID,
                entryID: entryID,
                valueType: .number,
                cardinality: .one,
                state: .value,
                revision: 7,
                value: .number("42"),
            ),
        ),
        (
            "cardinality",
            PropertyAssignment(
                propertyID: propertyID,
                entryID: entryID,
                valueType: .text,
                cardinality: .many,
                state: .value,
                revision: 7,
                value: .texts(["before"]),
            ),
        ),
        (
            "revision",
            PropertyAssignment(
                propertyID: propertyID,
                entryID: entryID,
                valueType: .text,
                cardinality: .one,
                state: .value,
                revision: 8,
                value: .text("before"),
            ),
        ),
        ("implicit unset", nil),
    ]
}

func requestAssemblyValidationClient(recorder: OperationRecorder) -> EntryCorePropertyClient {
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
        changePrepare: { _, _ in
            await recorder.record("prepare")
            throw EntryCoreClientError.daemonUnavailable
        },
        changeExecute: { _, _ in
            await recorder.record("execute")
            return []
        },
        conditionQuery: { _, _ in throw EntryCoreClientError.daemonUnavailable },
    )
}

func contractViolatingAssignmentClient(page: PropertyAssignmentPage) -> EntryCorePropertyClient {
    EntryCorePropertyClient(
        definitionList: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionReorder: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        assignmentList: { _, _ in page },
        changePrepare: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        changeExecute: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        conditionQuery: { _, _ in throw EntryCoreClientError.daemonUnavailable },
    )
}

func mismatchedPropertyClient(response: PropertyChangeProposal) -> EntryCorePropertyClient {
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

struct ReplacedEntryFixture {
    let selection: EntryPropertiesSelection
    let proposal: EntryPropertiesProposal
    let canonicalResult: EntryPropertiesCanonicalResult
}

/// /a의 entry가 교체된 selection과 이전 identity의 proposal·검증 결과다.
func replacedEntryFixture() throws -> ReplacedEntryFixture {
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
func mixedIdentitySnapshot() throws -> EntryPropertiesTargetSnapshot {
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
func mixedIdentityPreparedResponse() throws -> PropertyChangeProposal {
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
func mixedIdentityDifferences() throws -> [EntryPropertiesDifference] {
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

func prepareStubClient(response: PropertyChangeProposal) -> EntryCorePropertyClient {
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

func paginatingPropertyClient(
    definitionList: @escaping @Sendable (EntryCoreEndpoint, PropertyDefinitionListRequest) async throws
        -> PropertyDefinitionPage,
    assignmentList: @escaping @Sendable (EntryCoreEndpoint, PropertyAssignmentListRequest) async throws
        -> PropertyAssignmentPage,
) -> EntryCorePropertyClient {
    EntryCorePropertyClient(
        definitionList: definitionList,
        definitionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        definitionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionCreate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionUpdate: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionReorder: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        optionDisable: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        assignmentList: assignmentList,
        changePrepare: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        changeExecute: { _, _ in throw EntryCoreClientError.daemonUnavailable },
        conditionQuery: { _, _ in throw EntryCoreClientError.daemonUnavailable },
    )
}

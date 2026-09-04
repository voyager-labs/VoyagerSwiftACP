import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

/// condition query 페이지네이션의 진행 계약을 검증한다. daemon은 item 수가
/// 정확히 page_size에 도달한 뒤 candidate offset을 전진시킬 때만 has_more을
/// 설정한다(condition_query.go의 page completion 조건).
extension EntryCorePropertyClientFlowTests {
    /// has_more인 query page는 정확히 page_size를 채우고 전진하는 token을
    /// 가져야 한다. 그렇지 않으면 token 순회 caller가 같은 페이지를 무한
    /// 요청할 수 있다.
    func testQueryRejectsNonProgressivePage() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let condition = try PropertyCondition(
            propertyID: propertyID,
            operator: PropertyConditionOperator(rawValue: "exists"),
            operand: .none,
        )
        let targetA = try PropertyTarget(localPath: "/a")
        let targetB = try PropertyTarget(localPath: "/b")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let firstPageItem = "[\(paginationQueryItem(index: 0))]"
        let cases = try [
            PaginationCase(
                name: "has_more with under-filled page",
                request: makePaginationQueryRequest(
                    targets: [targetA, targetB], condition: condition, pageSize: 2,
                ),
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[]", hasMore: true, nextPageToken: "next",
                ),
            ),
            PaginationCase(
                name: "has_more with repeated token",
                request: makePaginationQueryRequest(
                    targets: [targetA, targetB],
                    condition: condition,
                    pageSize: 1,
                    pageToken: "same",
                    minCandidateIndex: 0,
                ),
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[]", hasMore: true, nextPageToken: "same",
                ),
            ),
            PaginationCase(
                name: "has_more cycling tokens with stale candidate index",
                request: makePaginationQueryRequest(
                    targets: [targetA, targetB],
                    condition: condition,
                    pageSize: 1,
                    pageToken: "a",
                    minCandidateIndex: 1,
                ),
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[]", hasMore: true, nextPageToken: "b",
                ),
            ),
            PaginationCase(
                name: "has_more with unresolved beyond the last matched candidate",
                request: makePaginationQueryRequest(
                    targets: [targetA, targetB], condition: condition, pageSize: 1,
                ),
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[1]", hasMore: true, nextPageToken: "next",
                ),
            ),
        ]
        try await assertQueryPaginationRejected(cases, endpoint: endpoint)

        // has_more가 아니면 마지막 matched 뒤의 unresolved도 유효하다(꼬리 미스).
        // terminal 페이지도 minCandidateIndex 하한을 적용한다 — 재생은 거절.
        let replayedTerminalRequest = try makePaginationQueryRequest(
            targets: [targetA, targetB],
            condition: condition,
            pageSize: 1,
            pageToken: "first",
            minCandidateIndex: 1,
        )
        let replayedTerminalCases = [
            PaginationCase(
                name: "terminal page replaying the request cursor",
                request: replayedTerminalRequest,
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[]", hasMore: false,
                ),
            ),
        ]
        try await assertQueryPaginationRejected(replayedTerminalCases, endpoint: endpoint)

        // 하한 이상인 terminal 페이지는 수용된다.
        let advancedTerminalResponse = queryPaginationPageResponse(
            items: "[\(paginationQueryItem(index: 1))]", unresolved: "[]", hasMore: false,
        )
        let advancedTerminalRecorder = PropertyTransportRecorder(
            response: Data(advancedTerminalResponse.utf8),
        )
        let advancedTerminalClient = EntryCorePropertyClient.makeLive(
            requestID: { "query-id" },
            makeTransport: advancedTerminalRecorder.makeTransport,
        )
        let advancedTerminalRequest = try makePaginationQueryRequest(
            targets: [targetA, targetB],
            condition: condition,
            pageSize: 1,
            pageToken: "first",
            minCandidateIndex: 1,
        )
        _ = try await advancedTerminalClient.conditionQuery(endpoint, advancedTerminalRequest)
        XCTAssertEqual(advancedTerminalRecorder.requests.count, 1)

        let tailMissResponse = queryPaginationPageResponse(
            items: firstPageItem, unresolved: "[1]", hasMore: false,
        )
        let tailMissRecorder = PropertyTransportRecorder(response: Data(tailMissResponse.utf8))
        let tailMissClient = EntryCorePropertyClient.makeLive(
            requestID: { "query-id" },
            makeTransport: tailMissRecorder.makeTransport,
        )
        let tailMissRequest = try makePaginationQueryRequest(
            targets: [targetA, targetB], condition: condition, pageSize: 1,
        )
        _ = try await tailMissClient.conditionQuery(endpoint, tailMissRequest)
        XCTAssertEqual(tailMissRecorder.requests.count, 1)

        // 전진하는 token을 가진 꽉 찬 페이지는 수용된다.
        let progressiveRequest = try makePaginationQueryRequest(
            targets: [targetA, targetB],
            condition: condition,
            pageSize: 1,
            pageToken: "first",
            minCandidateIndex: 1,
        )
        let progressiveItem = "[\(paginationQueryItem(index: 1))]"
        let progressiveResponse = queryPaginationPageResponse(
            items: progressiveItem, unresolved: "[]", hasMore: true, nextPageToken: "second",
        )
        let progressiveRecorder = PropertyTransportRecorder(response: Data(progressiveResponse.utf8))
        let progressiveClient = EntryCorePropertyClient.makeLive(
            requestID: { "query-id" },
            makeTransport: progressiveRecorder.makeTransport,
        )
        _ = try await progressiveClient.conditionQuery(endpoint, progressiveRequest)
        XCTAssertEqual(progressiveRecorder.requests.count, 1)
    }

    /// definition list의 has_more 페이지도 정확히 page_size를 채우고 전진하는
    /// token을 가져야 한다. 같은 token의 반복은 무한 요청으로 이어진다.
    func testDefinitionListPageRejectsNonProgressiveToken() async throws {
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let underFilledRequest = try PropertyDefinitionListRequest(pageSize: 2, includeDisabled: true)
        let repeatedRequest = try PropertyDefinitionListRequest(
            pageSize: 2, includeDisabled: true, pageToken: "same",
        )
        let id1 = "00000000-0000-0000-8000-000000000001"
        let id2 = "00000000-0000-0000-8000-000000000002"
        let cyclicRequest = try PropertyDefinitionListRequest(
            pageSize: 2, includeDisabled: true, pageToken: id2,
        )
        var cases = [
            DefinitionListCase(
                name: "has_more with under-filled page",
                request: underFilledRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 1))]",
                    hasMore: true,
                    nextPageToken: "next",
                ),
            ),
            DefinitionListCase(
                name: "has_more with repeated token",
                request: repeatedRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 1)),\(paginationDefinitionJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: "same",
                ),
            ),
            DefinitionListCase(
                name: "has_more with token not matching the last definition",
                request: cyclicRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 1)),\(paginationDefinitionJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: "00000000-0000-0000-8000-000000000003",
                ),
            ),
            DefinitionListCase(
                name: "has_more with non-advancing token",
                request: cyclicRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 1)),\(paginationDefinitionJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: id2,
                ),
            ),
            DefinitionListCase(
                name: "has_more with descending definitions",
                request: underFilledRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 2)),\(paginationDefinitionJSON(id: 1))]",
                    hasMore: true,
                    nextPageToken: "00000000-0000-0000-8000-000000000001",
                ),
            ),
        ]
        try await assertListPageRejected(cases, endpoint: endpoint)

        let acceptedRequest = try PropertyDefinitionListRequest(
            pageSize: 2, includeDisabled: true, pageToken: id1,
        )
        let acceptedResponse = definitionListPageResponse(
            definitions: "[\(paginationDefinitionJSON(id: 2))]",
            hasMore: false,
        )
        let replayedTerminalRequest = try PropertyDefinitionListRequest(
            pageSize: 2, includeDisabled: true, pageToken: id2,
        )
        cases.append(
            DefinitionListCase(
                name: "terminal page replaying the request cursor",
                request: replayedTerminalRequest,
                response: definitionListPageResponse(
                    definitions: "[\(paginationDefinitionJSON(id: 1)),\(paginationDefinitionJSON(id: 2))]",
                    hasMore: false,
                ),
            ),
        )
        try await assertListPageAccepted(acceptedRequest, response: acceptedResponse, endpoint: endpoint) {
            $0.definitions.count == 1
        }
    }

    /// assignment list의 has_more 페이지도 정확히 page_size를 채우고 전진하는
    /// token을 가져야 한다.
    func testAssignmentListPageRejectsNonProgressiveToken() async throws {
        let target = try PropertyTarget(localPath: "/a")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let underFilledRequest = try PropertyAssignmentListRequest(
            pageSize: 2, target: target, requestedPropertyIDs: [],
        )
        let repeatedRequest = try PropertyAssignmentListRequest(
            pageSize: 2, target: target, pageToken: "same", requestedPropertyIDs: [],
        )
        let id1 = "00000000-0000-0000-8000-000000000001"
        let id2 = "00000000-0000-0000-8000-000000000002"
        let cyclicRequest = try PropertyAssignmentListRequest(
            pageSize: 2, target: target, pageToken: id2, requestedPropertyIDs: [],
        )
        let cases = [
            AssignmentListCase(
                name: "has_more with under-filled page",
                request: underFilledRequest,
                response: assignmentListPageResponse(
                    assignments: "[\(paginationAssignmentJSON(id: 1))]",
                    hasMore: true,
                    nextPageToken: "next",
                ),
            ),
            AssignmentListCase(
                name: "has_more with repeated token",
                request: repeatedRequest,
                response: assignmentListPageResponse(
                    assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: "same",
                ),
            ),
            AssignmentListCase(
                name: "has_more with token not matching the last assignment",
                request: cyclicRequest,
                response: assignmentListPageResponse(
                    assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: "00000000-0000-0000-8000-000000000003",
                ),
            ),
            AssignmentListCase(
                name: "has_more with non-advancing token",
                request: cyclicRequest,
                response: assignmentListPageResponse(
                    assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
                    hasMore: true,
                    nextPageToken: id2,
                ),
            ),
            AssignmentListCase(
                name: "has_more with descending assignments",
                request: underFilledRequest,
                response: assignmentListPageResponse(
                    assignments: "[\(paginationAssignmentJSON(id: 2)),\(paginationAssignmentJSON(id: 1))]",
                    hasMore: true,
                    nextPageToken: "00000000-0000-0000-8000-000000000001",
                ),
            ),
        ]
        try await assertListPageRejected(cases, endpoint: endpoint)

        let acceptedRequest = try PropertyAssignmentListRequest(
            pageSize: 2, target: target, pageToken: id1, requestedPropertyIDs: [],
        )
        let acceptedResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 2))]",
            hasMore: false,
        )
        try await assertListPageAccepted(acceptedRequest, response: acceptedResponse, endpoint: endpoint) {
            $0.assignments.count == 1
        }
    }

    /// 필터된 assignment-list 요청도 ID 부분집합 검사 뒤 has_more 진행 검사를
    /// 통과해야 한다. 조기 반환은 반복 token을 승인하게 만든다.
    func testAssignmentListPageValidatesProgressWithPropertyIDFilter() async throws {
        let target = try PropertyTarget(localPath: "/a")
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let repeatedRequest = try PropertyAssignmentListRequest(
            pageSize: 2,
            target: target,
            pageToken: propertyID2.rawValue,
            requestedPropertyIDs: [propertyID1, propertyID2],
        )
        let repeatedResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
            hasMore: true,
            nextPageToken: propertyID2.rawValue,
        )
        try await assertListPageRejected(
            [
                AssignmentListCase(
                    name: "filtered has_more with repeated token",
                    request: repeatedRequest,
                    response: repeatedResponse,
                ),
            ],
            endpoint: endpoint,
        )

        let progressiveRequest = try PropertyAssignmentListRequest(
            pageSize: 2,
            target: target,
            pageToken: propertyID1.rawValue,
            requestedPropertyIDs: [propertyID1, propertyID2],
        )
        let progressiveResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 2))]",
            hasMore: false,
        )
        try await assertListPageAccepted(progressiveRequest, response: progressiveResponse, endpoint: endpoint) {
            $0.assignments.count == 1
        }
    }

    /// assignment-list 경로는 단일 local-path target을 한 entry로 해석해
    /// 조회한다. 서로 다른 entry의 값이 섞인 페이지는 생성 불가능한 응답이다.
    func testAssignmentListRejectsMixedEntryIds() async throws {
        let request = try PropertyAssignmentListRequest(
            pageSize: 2,
            target: PropertyTarget(localPath: "/a"),
            requestedPropertyIDs: [],
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let firstEntryID = "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let secondEntryID = "ent:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        let singleEntryRecorder = PropertyTransportRecorder(
            response: Data(assignmentEntriesPageJSON(entryIDs: [firstEntryID]).utf8),
        )
        let singleEntryClient = EntryCorePropertyClient.makeLive(
            requestID: { "list-id" },
            makeTransport: singleEntryRecorder.makeTransport,
        )
        let conflictingRecorder = PropertyTransportRecorder(
            response: Data(
                assignmentEntriesPageJSON(entryIDs: [firstEntryID, secondEntryID]).utf8,
            ),
        )
        let conflictingClient = EntryCorePropertyClient.makeLive(
            requestID: { "list-id" },
            makeTransport: conflictingRecorder.makeTransport,
        )
        do {
            _ = try await conflictingClient.assignmentList(endpoint, request)
            XCTFail("page mixing multiple entries should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(conflictingRecorder.requests.count, 1)

        let singleEntryPage = try await singleEntryClient.assignmentList(
            endpoint,
            PropertyAssignmentListRequest(
                pageSize: 2,
                target: PropertyTarget(localPath: "/a"),
                requestedPropertyIDs: [],
            ),
        )
        XCTAssertEqual(Set(singleEntryPage.assignments.map(\.entryID)).count, 1)
    }
}

private struct DefinitionListCase {
    let name: String
    let request: PropertyDefinitionListRequest
    let response: String
}

private struct AssignmentListCase {
    let name: String
    let request: PropertyAssignmentListRequest
    let response: String
}

/// definition mutation 요청의 사전 definition snapshot은 wire 인자와 정확히
/// 대응해야 한다. 어긋난 snapshot으로 기대 응답을 만들면 정상 daemon 응답도
/// 거절된다.
func testDefinitionMutationRequestsValidateExpectedDefinitionSnapshot() throws {
    let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
    let otherPropertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
    let validSnapshot = try PropertyDefinition(
        id: propertyID,
        key: "property-key",
        name: "Property name",
        valueType: .text,
        cardinality: .one,
        state: .active,
        origin: .userDefined,
        revision: 1,
        options: [],
        conditionCapability: .unsupported(.unsupportedValueContract),
    )

    func mutatedSnapshot(name: String? = nil, state: PropertyDefinitionState = .active, revision: Int64 = 1) throws
        -> PropertyDefinition
    {
        try PropertyDefinition(
            id: propertyID,
            key: "property-key",
            name: name ?? "Property name",
            valueType: .text,
            cardinality: .one,
            state: state,
            origin: .userDefined,
            revision: revision,
            options: [],
            conditionCapability: .unsupported(.unsupportedValueContract),
        )
    }

    let updateMismatched = try [
        SnapshotMismatchCase(
            name: "snapshot for another property",
            snapshotPropertyID: otherPropertyID,
            revision: 1,
            snapshot: mutatedSnapshot(),
        ),
        SnapshotMismatchCase(
            name: "snapshot with drifted revision",
            snapshotPropertyID: propertyID,
            revision: 5,
            snapshot: mutatedSnapshot(revision: 5),
        ),
        SnapshotMismatchCase(
            name: "disabled snapshot",
            snapshotPropertyID: propertyID,
            revision: 1,
            snapshot: mutatedSnapshot(state: .disabled),
        ),
    ]
    for mismatchCase in updateMismatched {
        do {
            _ = try PropertyDefinitionUpdateRequest(
                propertyID: mismatchCase.snapshotPropertyID,
                expectedDefinitionRevision: mismatchCase.revision,
                expectedDefinition: mismatchCase.snapshot,
                name: "Renamed",
            )
            XCTFail("\(mismatchCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, mismatchCase.name)
        }
    }

    let builtInSnapshot = try PropertyDefinition(
        id: propertyID,
        key: "property-key",
        name: "Property name",
        valueType: .text,
        cardinality: .one,
        state: .active,
        origin: .builtIn,
        revision: 1,
        options: [],
        conditionCapability: .unsupported(.sourceRuntimeUnavailable),
    )
    let disableMismatched = try [
        SnapshotMismatchCase(
            name: "snapshot for another property",
            snapshotPropertyID: otherPropertyID,
            revision: 1,
            snapshot: validSnapshot,
        ),
        SnapshotMismatchCase(
            name: "snapshot with drifted revision",
            snapshotPropertyID: propertyID,
            revision: 5,
            snapshot: validSnapshot,
        ),
        SnapshotMismatchCase(
            name: "disabled snapshot",
            snapshotPropertyID: propertyID,
            revision: 1,
            snapshot: mutatedSnapshot(state: .disabled),
        ),
        SnapshotMismatchCase(
            name: "built-in snapshot",
            snapshotPropertyID: propertyID,
            revision: 1,
            snapshot: builtInSnapshot,
        ),
    ]
    for mismatchCase in disableMismatched {
        do {
            _ = try PropertyDefinitionDisableRequest(
                propertyID: mismatchCase.snapshotPropertyID,
                expectedDefinitionRevision: mismatchCase.revision,
                expectedDefinition: mismatchCase.snapshot,
            )
            XCTFail("\(mismatchCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, mismatchCase.name)
        }
    }

    // 일치하는 snapshot은 수용된다.
    _ = try PropertyDefinitionUpdateRequest(
        propertyID: propertyID,
        expectedDefinitionRevision: 1,
        expectedDefinition: validSnapshot,
        name: "Renamed",
    )
    _ = try PropertyDefinitionDisableRequest(
        propertyID: propertyID,
        expectedDefinitionRevision: 1,
        expectedDefinition: validSnapshot,
    )
}

/// .value 변경의 desired와 caller 보존 contract가 어긋나면 daemon은 wire의
/// 올바른 desired로 정상 커밋하지만 execute read-back이 로컬 contract와
/// 대조해 실패로 보고한다. 전송 전에 거부해 이 불일치를 차단한다.
func testChangeTargetRejectsValueContractMismatch() throws {
    let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
    let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    let target = try PropertyTarget(localPath: "/a")

    let mismatched = [
        SnapshotContractMismatchCase(
            name: "text value with number contract",
            contractValueType: .number,
            contractCardinality: .one,
        ),
        SnapshotContractMismatchCase(
            name: "text value with many cardinality",
            contractValueType: nil,
            contractCardinality: .many,
        ),
    ]
    for mismatchCase in mismatched {
        let contractValueType = mismatchCase.contractValueType
        let contractCardinality = mismatchCase.contractCardinality
        let resolvedValueType = contractValueType ?? .text
        let resolvedCardinality = contractCardinality ?? .one
        do {
            _ = try PropertyChangeTarget(
                target: target,
                propertyID: propertyID,
                expectedDefinitionRevision: 1,
                expectedAssignmentRevision: 0,
                desired: .value(.text, .one, .text("v")),
                expectedValueContract: ExpectedValueContract(
                    valueType: resolvedValueType,
                    cardinality: resolvedCardinality,
                ),
                entryID: entryID,
            )
            XCTFail("\(mismatchCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, mismatchCase.name)
        }
    }

    // 일치하는 contract는 수용된다.
    _ = try PropertyChangeTarget(
        target: target,
        propertyID: propertyID,
        expectedDefinitionRevision: 1,
        expectedAssignmentRevision: 0,
        desired: .value(.text, .one, .text("v")),
        expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
        entryID: entryID,
    )
}

private struct SnapshotMismatchCase {
    let name: String
    let snapshotPropertyID: PropertyID
    let revision: Int64
    let snapshot: PropertyDefinition
}

private struct SnapshotContractMismatchCase {
    let name: String
    let contractValueType: PropertyValueType?
    let contractCardinality: PropertyCardinality?
}

private func assertListPageRejected(
    _ cases: [DefinitionListCase],
    endpoint: EntryCoreEndpoint,
) async throws {
    for paginationCase in cases {
        let recorder = PropertyTransportRecorder(response: Data(paginationCase.response.utf8))
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "list-id" },
            makeTransport: recorder.makeTransport,
        )
        do {
            _ = try await client.definitionList(endpoint, paginationCase.request)
            XCTFail("\(paginationCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, paginationCase.name)
        }
        XCTAssertEqual(recorder.requests.count, 1, paginationCase.name)
    }
}

private func assertListPageRejected(
    _ cases: [AssignmentListCase],
    endpoint: EntryCoreEndpoint,
) async throws {
    for paginationCase in cases {
        let recorder = PropertyTransportRecorder(response: Data(paginationCase.response.utf8))
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "list-id" },
            makeTransport: recorder.makeTransport,
        )
        do {
            _ = try await client.assignmentList(endpoint, paginationCase.request)
            XCTFail("\(paginationCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, paginationCase.name)
        }
        XCTAssertEqual(recorder.requests.count, 1, paginationCase.name)
    }
}

private func assertListPageAccepted(
    _ request: PropertyDefinitionListRequest,
    response: String,
    endpoint: EntryCoreEndpoint,
    assertion: (PropertyDefinitionPage) -> Bool,
) async throws {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "list-id" },
        makeTransport: recorder.makeTransport,
    )
    let page = try await client.definitionList(endpoint, request)
    XCTAssertTrue(assertion(page))
    XCTAssertEqual(recorder.requests.count, 1)
}

private func assertListPageAccepted(
    _ request: PropertyAssignmentListRequest,
    response: String,
    endpoint: EntryCoreEndpoint,
    assertion: (PropertyAssignmentPage) -> Bool,
) async throws {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "list-id" },
        makeTransport: recorder.makeTransport,
    )
    let page = try await client.assignmentList(endpoint, request)
    XCTAssertTrue(assertion(page))
    XCTAssertEqual(recorder.requests.count, 1)
}

private func paginationDefinitionJSON(id: Int) -> String {
    """
    {
      "property_id":"00000000-0000-0000-8000-00000000000\(id)",
      "key":"paginated-key-\(id)","name":"paginated name",
      "value_type":"text","cardinality":"one","state":"disabled","origin":"user_defined",
      "revision":1,"options":[],
      "condition_capability":{"supported":false,"reason":"definition_disabled"}
    }
    """
}

private func paginationAssignmentJSON(id: Int) -> String {
    """
    {
      "property_id":"00000000-0000-0000-8000-00000000000\(id)",
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "value_type":"text","cardinality":"one","state":"null","revision":1
    }
    """
}

private func definitionListPageResponse(
    definitions: String,
    hasMore: Bool,
    nextPageToken: String? = nil,
) -> String {
    let tokenField = nextPageToken.map { "\"next_page_token\":\"\($0)\"," } ?? ""
    return """
    {
      "request_id":"list-id",
      "ok":true,
      "result":{"definitions":\(definitions),\(tokenField)"has_more":\(hasMore)}
    }
    """
}

private func assignmentListPageResponse(
    assignments: String,
    hasMore: Bool,
    nextPageToken: String? = nil,
) -> String {
    let tokenField = nextPageToken.map { "\"next_page_token\":\"\($0)\"," } ?? ""
    return """
    {
      "request_id":"list-id",
      "ok":true,
      "result":{"assignments":\(assignments),\(tokenField)"has_more":\(hasMore)}
    }
    """
}

private struct PaginationCase {
    let name: String
    let request: PropertyConditionQueryRequest
    let response: String
}

private func assertQueryPaginationRejected(
    _ cases: [PaginationCase],
    endpoint: EntryCoreEndpoint,
) async throws {
    for paginationCase in cases {
        let recorder = PropertyTransportRecorder(response: Data(paginationCase.response.utf8))
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "query-id" },
            makeTransport: recorder.makeTransport,
        )

        do {
            _ = try await client.conditionQuery(endpoint, paginationCase.request)
            XCTFail("\(paginationCase.name) should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, paginationCase.name)
        }
        XCTAssertEqual(recorder.requests.count, 1, paginationCase.name)
    }
}

private func makePaginationQueryRequest(
    targets: [PropertyTarget],
    condition: PropertyCondition,
    pageSize: Int,
    pageToken: String? = nil,
    minCandidateIndex: Int? = nil,
) throws -> PropertyConditionQueryRequest {
    try PropertyConditionQueryRequest(
        targets: targets,
        combinator: .all,
        conditions: [condition],
        evaluationDate: "2026-09-01",
        pageSize: pageSize,
        pageToken: pageToken,
        minCandidateIndex: minCandidateIndex,
    )
}

private func paginationQueryItem(index: Int) -> String {
    """
    {
      "candidate_index":\(index),
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "projection":[]
    }
    """
}

private func queryPaginationPageResponse(
    items: String,
    unresolved: String,
    hasMore: Bool,
    nextPageToken: String? = nil,
) -> String {
    let tokenField = nextPageToken.map { "\"next_page_token\":\"\($0)\"," } ?? ""
    return """
    {
      "request_id":"query-id",
      "ok":true,
      "result":{
        "items":\(items),
        "unresolved_candidate_indices":\(unresolved),
        \(tokenField)
        "catalog_version":"2.2.0",
        "has_more":\(hasMore)
      }
    }
    """
}

private func assignmentEntriesPageJSON(entryIDs: [String]) -> String {
    var assignments = ""
    for (index, entryID) in entryIDs.enumerated() {
        let propertyID = "00000000-0000-0000-8000-00000000000\(index + 1)"
        assignments += "      {\"property_id\":\"\(propertyID)\","
        assignments += "\"entry_id\":\"\(entryID)\",\"value_type\":\"text\","
        assignments += "\"cardinality\":\"one\",\"state\":\"null\",\"revision\":1},"
        if index == entryIDs.count - 1 {
            assignments = String(assignments.dropLast())
        }
        assignments += "\n"
    }
    return """
    {
      "request_id":"list-id",
      "ok":true,
      "result":{
        "assignments":[
    \(assignments)
        ],
        "has_more":false
      }
    }
    """
}

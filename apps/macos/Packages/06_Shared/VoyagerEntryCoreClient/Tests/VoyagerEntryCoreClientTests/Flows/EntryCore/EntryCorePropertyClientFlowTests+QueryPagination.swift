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
                    targets: [targetA, targetB], condition: condition, pageSize: 1, pageToken: "same",
                ),
                response: queryPaginationPageResponse(
                    items: firstPageItem, unresolved: "[]", hasMore: true, nextPageToken: "same",
                ),
            ),
        ]
        try await assertQueryPaginationRejected(cases, endpoint: endpoint)

        // 전진하는 token을 가진 꽉 찬 페이지는 수용된다.
        let progressiveRequest = try makePaginationQueryRequest(
            targets: [targetA, targetB], condition: condition, pageSize: 1, pageToken: "first",
        )
        let progressiveResponse = queryPaginationPageResponse(
            items: firstPageItem, unresolved: "[]", hasMore: true, nextPageToken: "second",
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
        let cases = [
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
        ]
        try await assertListPageRejected(cases, endpoint: endpoint)

        let acceptedRequest = try PropertyDefinitionListRequest(
            pageSize: 2, includeDisabled: true, pageToken: "first",
        )
        let acceptedResponse = definitionListPageResponse(
            definitions: "[\(paginationDefinitionJSON(id: 1)),\(paginationDefinitionJSON(id: 2))]",
            hasMore: true,
            nextPageToken: "second",
        )
        try await assertListPageAccepted(acceptedRequest, response: acceptedResponse, endpoint: endpoint) {
            $0.definitions.count == 2
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
        ]
        try await assertListPageRejected(cases, endpoint: endpoint)

        let acceptedRequest = try PropertyAssignmentListRequest(
            pageSize: 2, target: target, pageToken: "first", requestedPropertyIDs: [],
        )
        let acceptedResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
            hasMore: true,
            nextPageToken: "second",
        )
        try await assertListPageAccepted(acceptedRequest, response: acceptedResponse, endpoint: endpoint) {
            $0.assignments.count == 2
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
            pageToken: "same",
            requestedPropertyIDs: [propertyID1, propertyID2],
        )
        let repeatedResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
            hasMore: true,
            nextPageToken: "same",
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
            pageToken: "first",
            requestedPropertyIDs: [propertyID1, propertyID2],
        )
        let progressiveResponse = assignmentListPageResponse(
            assignments: "[\(paginationAssignmentJSON(id: 1)),\(paginationAssignmentJSON(id: 2))]",
            hasMore: true,
            nextPageToken: "second",
        )
        try await assertListPageAccepted(progressiveRequest, response: progressiveResponse, endpoint: endpoint) {
            $0.assignments.count == 2
        }
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

private func definitionListPageResponse(definitions: String, hasMore: Bool, nextPageToken: String) -> String {
    """
    {
      "request_id":"list-id",
      "ok":true,
      "result":{"definitions":\(definitions),"next_page_token":"\(nextPageToken)","has_more":\(hasMore)}
    }
    """
}

private func assignmentListPageResponse(assignments: String, hasMore: Bool, nextPageToken: String) -> String {
    """
    {
      "request_id":"list-id",
      "ok":true,
      "result":{"assignments":\(assignments),"next_page_token":"\(nextPageToken)","has_more":\(hasMore)}
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
) throws -> PropertyConditionQueryRequest {
    try PropertyConditionQueryRequest(
        targets: targets,
        combinator: .all,
        conditions: [condition],
        evaluationDate: "2026-09-01",
        pageSize: pageSize,
        pageToken: pageToken,
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
    nextPageToken: String,
) -> String {
    """
    {
      "request_id":"query-id",
      "ok":true,
      "result":{
        "items":\(items),
        "unresolved_candidate_indices":\(unresolved),
        "next_page_token":"\(nextPageToken)",
        "catalog_version":"2.2.0",
        "has_more":\(hasMore)
      }
    }
    """
}

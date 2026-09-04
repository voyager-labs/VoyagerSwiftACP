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

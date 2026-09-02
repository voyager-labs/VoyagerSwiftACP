import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

final class EntryCorePropertyClientFlowTests: XCTestCase {
    func testQueryUsesFreshTransportOnceAndEncodesExactTypedParams() async throws {
        let response = Data(propertyJSON(
            #"{"request_id":"query-id","ok":true,"result":{"items":[],"#,
            #""unresolved_candidate_indices":[],"catalog_version":"2.2.0","has_more":false}}"#,
        ).utf8)
        let recorder = PropertyTransportRecorder(response: response)
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "query-id" },
            makeTransport: recorder.makeTransport,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let condition = try PropertyCondition(
            propertyID: propertyID,
            operator: PropertyConditionOperator(rawValue: "exists"),
            operand: .none,
        )
        let request = try PropertyConditionQueryRequest(
            targets: [PropertyTarget(localPath: "/a")],
            combinator: .all,
            conditions: [condition],
            evaluationDate: "2026-09-01",
            pageSize: 32,
            projectionPropertyIDs: [propertyID],
        )

        _ = try await client.conditionQuery(endpoint, request)

        XCTAssertEqual(recorder.creationCount, 1)
        XCTAssertEqual(recorder.requests.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: recorder.requests[0]) as? [String: Any],
        )
        XCTAssertEqual(object["request_id"] as? String, "query-id")
        XCTAssertEqual(object["method"] as? String, "property.condition.query")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        XCTAssertEqual(params["evaluation_date"] as? String, "2026-09-01")
        XCTAssertEqual(params["page_size"] as? Int, 32)
    }

    func testQueryRejectsResponseOutsideRequestContext() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let condition = try PropertyCondition(
            propertyID: propertyID,
            operator: PropertyConditionOperator(rawValue: "exists"),
            operand: .none,
        )
        let cases = try makeQueryContextMismatchCases(condition: condition)
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        for testCase in cases {
            let recorder = PropertyTransportRecorder(response: Data(testCase.response.utf8))
            let client = EntryCorePropertyClient.makeLive(
                requestID: { "query-id" },
                makeTransport: recorder.makeTransport,
            )

            do {
                _ = try await client.conditionQuery(endpoint, testCase.request)
                XCTFail("\(testCase.name) should be rejected")
            } catch {
                XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, testCase.name)
            }
            XCTAssertEqual(recorder.creationCount, 1, testCase.name)
            XCTAssertEqual(recorder.requests.count, 1, testCase.name)
        }
    }

    func testInvalidLocalBoundsDoNotCreateTransport() throws {
        let recorder = PropertyTransportRecorder(response: Data())
        _ = EntryCorePropertyClient.makeLive(
            requestID: { "unused" },
            makeTransport: recorder.makeTransport,
        )
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let condition = try PropertyCondition(
            propertyID: propertyID,
            operator: PropertyConditionOperator(rawValue: "exists"),
            operand: .text(["wrong"]),
        )
        XCTAssertThrowsError(try PropertyConditionQueryRequest(
            targets: [PropertyTarget(localPath: "/a")],
            combinator: .all,
            conditions: [condition],
            evaluationDate: "2026-09-01",
            pageSize: 1,
        ))
        XCTAssertEqual(recorder.creationCount, 0)
    }

    func testPropertyChangeRejectsInvalidPayloadBeforeTransport() throws {
        let recorder = PropertyTransportRecorder(response: Data())
        _ = EntryCorePropertyClient.makeLive(
            requestID: { "unused" },
            makeTransport: recorder.makeTransport,
        )
        let target = try PropertyTarget(localPath: "/a")
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")

        let invalidDesiredStates: [PropertyDesiredState] = [
            .value(.number, .one, .number("01")),
            .value(.date, .one, .date("2026-02-30")),
            .value(.datetime, .one, .dateTime("2026-08-03T10:02:03.100Z")),
            .value(.text, .one, .text(String(repeating: "x", count: 4097))),
            .value(.text, .many, .texts(Array(repeating: "x", count: 257))),
        ]

        for desired in invalidDesiredStates {
            XCTAssertThrowsError(try PropertyChangeTarget(
                target: target,
                propertyID: propertyID,
                expectedDefinitionRevision: 1,
                expectedAssignmentRevision: 0,
                desired: desired,
            ))
        }
        XCTAssertEqual(recorder.creationCount, 0)
    }

    func testOversizedEncodedPropertyRequestDoesNotCreateTransport() async throws {
        let recorder = PropertyTransportRecorder(response: Data())
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "unused" },
            makeTransport: recorder.makeTransport,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let target = try PropertyTarget(localPath: "/a")
        let value = String(repeating: "x", count: 4096)
        let desired = PropertyDesiredState.value(.text, .many, .texts(Array(repeating: value, count: 256)))
        let change = try PropertyChangeTarget(
            target: target,
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: desired,
        )
        let request = try PropertyChangeRequest(changes: [change])

        do {
            _ = try await client.changePrepare(endpoint, request)
            XCTFail("oversized request should be rejected before transport")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(recorder.creationCount, 0)
        XCTAssertEqual(recorder.requests, [])
    }
}

private struct QueryContextMismatchCase {
    let name: String
    let request: PropertyConditionQueryRequest
    let response: String
}

private func makeQueryRequest(
    targets: [PropertyTarget],
    condition: PropertyCondition,
    pageSize: Int,
) throws -> PropertyConditionQueryRequest {
    try PropertyConditionQueryRequest(
        targets: targets,
        combinator: .all,
        conditions: [condition],
        evaluationDate: "2026-09-01",
        pageSize: pageSize,
    )
}

private func makeQueryContextMismatchCases(
    condition: PropertyCondition,
) throws -> [QueryContextMismatchCase] {
    let targetA = try PropertyTarget(localPath: "/a")
    let targetB = try PropertyTarget(localPath: "/b")
    let outOfRangeItem = queryItem(index: 1)
    let tooManyItems = "[\(queryItem(index: 0)),\(queryItem(index: 1))]"
    let projection = #"""
    [{
      "property_id": "00000000-0000-0000-8000-000000000001",
      "entry_id": "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "value_type": "text",
      "cardinality": "one",
      "state": "null",
      "revision": 1
    }]
    """#
    let unrequestedProjection = queryItem(index: 0, projection: projection)
    return try [
        QueryContextMismatchCase(
            name: "candidate index out of range",
            request: makeQueryRequest(targets: [targetA], condition: condition, pageSize: 1),
            response: queryPageResponse(items: "[\(outOfRangeItem)]", unresolved: "[]"),
        ),
        QueryContextMismatchCase(
            name: "page contains too many items",
            request: makeQueryRequest(targets: [targetA, targetB], condition: condition, pageSize: 1),
            response: queryPageResponse(items: tooManyItems, unresolved: "[]"),
        ),
        QueryContextMismatchCase(
            name: "projection contains an unrequested property",
            request: makeQueryRequest(targets: [targetA], condition: condition, pageSize: 1),
            response: queryPageResponse(items: "[\(unrequestedProjection)]", unresolved: "[]"),
        ),
        QueryContextMismatchCase(
            name: "unresolved index out of range",
            request: makeQueryRequest(targets: [targetA], condition: condition, pageSize: 1),
            response: queryPageResponse(items: "[]", unresolved: "[1]"),
        ),
        QueryContextMismatchCase(
            name: "item and unresolved index overlap",
            request: makeQueryRequest(targets: [targetA], condition: condition, pageSize: 1),
            response: queryPageResponse(items: "[\(queryItem(index: 0))]", unresolved: "[0]"),
        ),
    ]
}

private func queryItem(index: Int, projection: String = "[]") -> String {
    """
    {
      "candidate_index":\(index),
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "projection":\(projection)
    }
    """
}

private func queryPageResponse(items: String, unresolved: String) -> String {
    """
    {
      "request_id":"query-id",
      "ok":true,
      "result":{
        "items":\(items),
        "unresolved_candidate_indices":\(unresolved),
        "catalog_version":"2.2.0",
        "has_more":false
      }
    }
    """
}

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
}

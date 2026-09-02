import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

final class EntryCorePropertyProtocolFlowTests: XCTestCase {
    func testConditionQueryDecodesStrictTypedResult() throws {
        let wire = Data(propertyJSON(
            #"{"request_id":"id","ok":true,"result":{"items":[],"#,
            #""unresolved_candidate_indices":[1],"catalog_version":"2.2.0","has_more":false}}"#,
        ).utf8)
        let result = try EntryCorePropertyResponseDecoder.decode(
            Array(wire),
            method: .propertyConditionQuery,
            expectedRequestID: "id",
        )
        XCTAssertEqual(
            result,
            .queryPage(PropertyConditionQueryPage(
                items: [],
                unresolvedCandidateIndices: [1],
                catalogVersion: "2.2.0",
                nextPageToken: nil,
                hasMore: false,
            )),
        )
    }

    func testConditionQueryRejectsUnknownResultFieldAndEnum() {
        let unknownField = Data(propertyJSON(
            #"{"request_id":"id","ok":true,"result":{"items":[],"#,
            #""unresolved_candidate_indices":[],"catalog_version":"2.2.0","has_more":false,"future":1}}"#,
        ).utf8)
        XCTAssertThrowsError(
            try EntryCorePropertyResponseDecoder.decode(
                Array(unknownField),
                method: .propertyConditionQuery,
                expectedRequestID: "id",
            ),
        ) {
            XCTAssertEqual($0 as? EntryCoreClientError, .protocolMismatch)
        }

        let unknownCapability = Data(propertyJSON(
            #"{"request_id":"id","ok":true,"result":{"definitions":[{"#,
            #""property_id":"00000000-0000-0000-8000-000000000001","key":"k","name":"n","#,
            #""value_type":"text","cardinality":"one","state":"active","revision":1,"options":[],"#,
            #""condition_capability":{"supported":false,"reason":"future"}}],"has_more":false}}"#,
        ).utf8)
        XCTAssertThrowsError(
            try EntryCorePropertyResponseDecoder.decode(
                Array(unknownCapability),
                method: .propertyDefinitionList,
                expectedRequestID: "id",
            ),
        ) {
            XCTAssertEqual($0 as? EntryCoreClientError, .protocolMismatch)
        }
    }

    func testPrepareRejectsBeforeIdentityMismatch() throws {
        let propertyID = "00000000-0000-0000-8000-000000000001"
        let otherPropertyID = "00000000-0000-0000-8000-000000000002"
        let entryID = "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let otherEntryID = "ent:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
        let responses = [
            prepareResponse(beforePropertyID: otherPropertyID, beforeEntryID: entryID),
            prepareResponse(beforePropertyID: propertyID, beforeEntryID: otherEntryID),
        ]

        for wire in responses {
            XCTAssertThrowsError(
                try EntryCorePropertyResponseDecoder.decode(
                    Array(wire),
                    method: .propertyChangePrepare,
                    expectedRequestID: "id",
                ),
            ) {
                XCTAssertEqual($0 as? EntryCoreClientError, .protocolMismatch)
            }
        }
    }

    func testAssignmentDecodesRFC3339NanoFractionalDatetime() throws {
        let wire = Data(
            #"""
            {"request_id":"id","ok":true,"result":{"assignments":[{
                "property_id":"00000000-0000-0000-8000-000000000001",
                "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                "value_type":"datetime","cardinality":"one","state":"value","revision":1,
                "value":"2026-08-03T10:02:03.1Z"
            }]}}
            """#.utf8,
        )
        let result = try EntryCorePropertyResponseDecoder.decode(
            Array(wire),
            method: .propertyChangeExecute,
            expectedRequestID: "id",
        )

        guard case let .assignments(assignments) = result else {
            return XCTFail("expected assignment result")
        }
        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].value, .dateTime("2026-08-03T10:02:03.1Z"))
    }

    func testAssignmentRejectsOversizedManyTextMember() throws {
        let oversizedText = String(repeating: "x", count: 4097)
        let object: [String: Any] = [
            "request_id": "id",
            "ok": true,
            "result": [
                "assignments": [
                    [
                        "property_id": "00000000-0000-0000-8000-000000000001",
                        "entry_id": "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
                        "value_type": "text",
                        "cardinality": "many",
                        "state": "value",
                        "revision": 1,
                        "value": [oversizedText],
                    ],
                ],
            ],
        ]
        let wire = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try EntryCorePropertyResponseDecoder.decode(
                Array(wire),
                method: .propertyChangeExecute,
                expectedRequestID: "id",
            ),
        ) {
            XCTAssertEqual($0 as? EntryCoreClientError, .protocolMismatch)
        }
    }
}

private func prepareResponse(beforePropertyID: String, beforeEntryID: String) -> Data {
    Data(
        """
        {
          "request_id":"id",
          "ok":true,
          "result":{
            "changes":[{
              "target":{"kind":"local_path","local_path":"/a"},
              "property_id":"00000000-0000-0000-8000-000000000001",
              "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
              "before":{
                "property_id":"\(beforePropertyID)",
                "entry_id":"\(beforeEntryID)",
                "value_type":"text",
                "cardinality":"one",
                "state":"null",
                "revision":1
              },
              "after":{"state":"null"}
            }],
            "requires_confirmation":true
          }
        }
        """.utf8,
    )
}

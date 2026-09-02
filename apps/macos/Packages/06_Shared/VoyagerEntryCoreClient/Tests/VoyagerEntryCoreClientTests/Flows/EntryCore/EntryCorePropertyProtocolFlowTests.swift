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
}

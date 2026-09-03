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

    func testCapabilityAcceptsExactDefinitionValueContract() throws {
        let wire = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: PropertyConditionRelation.operators(for: .string).map(\.rawValue),
        )
        XCTAssertNoThrow(
            try EntryCorePropertyResponseDecoder.decode(
                Array(wire),
                method: .propertyDefinitionList,
                expectedRequestID: "id",
            ),
        )
    }

    func testCapabilityRejectsDefinitionContractMismatch() throws {
        let wrongNative = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "boolean",
            operators: PropertyConditionRelation.operators(for: .boolean).map(\.rawValue),
        )
        assertProtocolMismatch(wrongNative)

        let wrongOperators = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: ["rx"],
        )
        assertProtocolMismatch(wrongOperators)

        let unsupportedValueContract = try propertyDefinitionPageResponse(
            valueType: "datetime",
            cardinality: "one",
            nativeType: "date",
            operators: PropertyConditionRelation.operators(for: .date).map(\.rawValue),
        )
        assertProtocolMismatch(unsupportedValueContract)
    }

    func testCapabilityRejectsDefinitionLifecycleMismatch() throws {
        let disabledSupported = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: PropertyConditionRelation.operators(for: .string).map(\.rawValue),
            state: "disabled",
        )
        assertProtocolMismatch(disabledSupported)

        let activeDefinitionDisabled = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: [],
            conditionCapability: [
                "supported": false,
                "reason": "definition_disabled",
            ],
        )
        assertProtocolMismatch(activeDefinitionDisabled)

        let disabledRuntimeUnavailable = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: [],
            state: "disabled",
            conditionCapability: [
                "supported": false,
                "reason": "source_runtime_unavailable",
            ],
        )
        assertProtocolMismatch(disabledRuntimeUnavailable)
    }

    func testCapabilityAcceptsDefinitionLifecycleAlignedReasons() throws {
        let disabled = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: [],
            state: "disabled",
            conditionCapability: [
                "supported": false,
                "reason": "definition_disabled",
            ],
        )
        XCTAssertNoThrow(
            try EntryCorePropertyResponseDecoder.decode(
                Array(disabled),
                method: .propertyDefinitionList,
                expectedRequestID: "id",
            ),
        )

        let activeRuntimeUnavailable = try propertyDefinitionPageResponse(
            valueType: "text",
            cardinality: "one",
            nativeType: "string",
            operators: [],
            conditionCapability: [
                "supported": false,
                "reason": "source_runtime_unavailable",
            ],
        )
        XCTAssertNoThrow(
            try EntryCorePropertyResponseDecoder.decode(
                Array(activeRuntimeUnavailable),
                method: .propertyDefinitionList,
                expectedRequestID: "id",
            ),
        )
    }
}

private func assertProtocolMismatch(
    _ wire: Data,
    file: StaticString = #filePath,
    line: UInt = #line,
) {
    XCTAssertThrowsError(
        try EntryCorePropertyResponseDecoder.decode(
            Array(wire),
            method: .propertyDefinitionList,
            expectedRequestID: "id",
        ),
        file: file,
        line: line,
    ) {
        XCTAssertEqual($0 as? EntryCoreClientError, .protocolMismatch, file: file, line: line)
    }
}

private func propertyDefinitionPageResponse(
    valueType: String,
    cardinality: String,
    nativeType: String,
    operators: [String],
    state: String = "active",
    conditionCapability: [String: Any]? = nil,
) throws -> Data {
    let capability = conditionCapability ?? [
        "supported": true,
        "evaluation_scope": "local_assignment",
        "catalog_version": "2.2.0",
        "native_type": nativeType,
        "allowed_operators": operators,
    ]
    let definition: [String: Any] = [
        "property_id": "00000000-0000-0000-8000-000000000001",
        "key": "k",
        "name": "n",
        "value_type": valueType,
        "cardinality": cardinality,
        "state": state,
        "revision": 1,
        "options": [],
        "condition_capability": capability,
    ]
    let object: [String: Any] = [
        "request_id": "id",
        "ok": true,
        "result": [
            "definitions": [definition],
            "has_more": false,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: object)
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

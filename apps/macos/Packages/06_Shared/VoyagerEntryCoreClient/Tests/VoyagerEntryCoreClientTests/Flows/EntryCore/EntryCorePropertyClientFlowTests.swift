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

    func testExecuteRejectsResponseOutsideRequestChanges() async throws {
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let propertyID3 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000003")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let change1 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID1,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
            entryID: entryID,
        )
        let change2 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/b"),
            propertyID: propertyID2,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
            entryID: entryID,
        )
        let request = try PropertyChangeRequest(changes: [change1, change2])
        let cases = executeResponseCases(
            propertyID1: propertyID1,
            propertyID2: propertyID2,
            propertyID3: propertyID3,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        for (name, response) in cases {
            let recorder = PropertyTransportRecorder(response: Data(response.utf8))
            let client = EntryCorePropertyClient.makeLive(
                requestID: { "execute-id" },
                makeTransport: recorder.makeTransport,
            )

            do {
                _ = try await client.changeExecute(endpoint, request)
                XCTFail("\(name) should be rejected")
            } catch {
                XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, name)
            }
            XCTAssertEqual(recorder.creationCount, 1, name)
            XCTAssertEqual(recorder.requests.count, 1, name)
        }
    }

    func testAssignmentListRejectsResponseOutsideRequestContext() async throws {
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let target = try PropertyTarget(localPath: "/a")
        let twoAssignments = [
            propertyAssignmentJSON(propertyID: propertyID1.rawValue),
            propertyAssignmentJSON(propertyID: propertyID2.rawValue),
        ].joined(separator: ",")
        let cases = try [
            AssignmentListContextCase(
                name: "page contains too many assignments",
                request: PropertyAssignmentListRequest(
                    pageSize: 1,
                    target: target,
                    requestedPropertyIDs: [propertyID1, propertyID2],
                ),
                response: assignmentPageResponse(
                    assignments: "[\(twoAssignments)]",
                ),
            ),
            AssignmentListContextCase(
                name: "page contains an unrequested property",
                request: PropertyAssignmentListRequest(
                    pageSize: 2,
                    target: target,
                    requestedPropertyIDs: [propertyID1],
                ),
                response: assignmentPageResponse(
                    assignments: "[\(propertyAssignmentJSON(propertyID: propertyID2.rawValue))]",
                ),
            ),
        ]

        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        for testCase in cases {
            let recorder = PropertyTransportRecorder(response: Data(testCase.response.utf8))
            let client = EntryCorePropertyClient.makeLive(
                requestID: { "assignment-id" },
                makeTransport: recorder.makeTransport,
            )

            do {
                _ = try await client.assignmentList(endpoint, testCase.request)
                XCTFail("\(testCase.name) should be rejected")
            } catch {
                XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, testCase.name)
            }
            XCTAssertEqual(recorder.creationCount, 1, testCase.name)
            XCTAssertEqual(recorder.requests.count, 1, testCase.name)
        }
    }

    func testDefinitionListRejectsResponseOutsideRequestContext() async throws {
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let cases = try definitionListContextCases(
            propertyID1: propertyID1,
            propertyID2: propertyID2,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        for testCase in cases {
            let recorder = PropertyTransportRecorder(response: Data(testCase.response.utf8))
            let client = EntryCorePropertyClient.makeLive(
                requestID: { "definition-id" },
                makeTransport: recorder.makeTransport,
            )

            do {
                _ = try await client.definitionList(endpoint, testCase.request)
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
            XCTAssertEqual(error as? EntryCoreClientError, .localValidation)
        }
        XCTAssertEqual(recorder.creationCount, 0)
        XCTAssertEqual(recorder.requests, [])
    }
}

extension EntryCorePropertyClientFlowTests {
    func testDefinitionMutationsRejectIdentityAndRevisionMismatches() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let otherPropertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let updateRequest = try PropertyDefinitionUpdateRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            name: "Renamed",
        )

        await assertDefinitionMutationRejected(
            "definition update property mismatch",
            request: updateRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: otherPropertyID.rawValue,
                    state: "active",
                    name: "Renamed",
                    revision: 2,
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.definitionUpdate(endpoint, request)
            },
        )

        let disableRequest = try PropertyDefinitionDisableRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
        )
        await assertDefinitionMutationRejected(
            "definition disable revision mismatch",
            request: disableRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "disabled",
                    revision: 1,
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.definitionDisable(endpoint, request)
            },
        )
    }

    func testDefinitionMutationsRejectResponsesOutsideRequestContext() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let updateRequest = try PropertyDefinitionUpdateRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            name: "Renamed",
        )
        await assertDefinitionMutationRejected(
            "definition update name mismatch",
            request: updateRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "active",
                    name: "Other name",
                    revision: 2,
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.definitionUpdate(endpoint, request)
            },
        )

        let disableRequest = try PropertyDefinitionDisableRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
        )
        await assertDefinitionMutationRejected(
            "definition disable state mismatch",
            request: disableRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "active",
                    revision: 2,
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.definitionDisable(endpoint, request)
            },
        )
    }

    func testOptionCreateAndUpdateRejectResponsesOutsideRequestContext() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let optionID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let existingOptions = propertyOptionJSON(id: optionID.rawValue, label: "Existing", position: 1)
        let wrongNewOption = propertyOptionJSON(
            id: "00000000-0000-7000-8000-000000000002", label: "Wrong label", position: 2,
        )

        let optionCreateRequest = try PropertyOptionCreateRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedOptions: [
                PropertyOption(id: optionID, label: "Existing", position: 1, state: .active),
            ],
            label: "Created",
        )
        await assertOptionCreateLabelMismatchRejected(
            request: optionCreateRequest,
            existingOptions: existingOptions,
            wrongNewOption: wrongNewOption,
            propertyID: propertyID.rawValue,
            endpoint: endpoint,
        )

        let optionUpdateRequest = try PropertyOptionUpdateRequest(
            propertyID: propertyID,
            optionID: optionID,
            expectedDefinitionRevision: 1,
            expectedOptions: [
                PropertyOption(id: optionID, label: "Existing", position: 1, state: .active),
            ],
            label: "Renamed option",
        )
        await assertDefinitionMutationRejected(
            "option update label mismatch",
            request: optionUpdateRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "active",
                    revision: 2,
                    valueType: "select",
                    options: "[\(existingOptions)]",
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.optionUpdate(endpoint, request)
            },
        )
    }

    func testOptionReorderRejectsResponsesOutsideRequestContext() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let optionID1 = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let optionID2 = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let reorderRequest = try PropertyOptionReorderRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            optionIDs: [optionID2, optionID1],
            expectedOptions: [
                PropertyOption(id: optionID1, label: "First", position: 1, state: .active),
                PropertyOption(id: optionID2, label: "Second", position: 2, state: .active),
            ],
        )
        let originalOrder = [
            propertyOptionJSON(id: optionID1.rawValue, label: "First", position: 1),
            propertyOptionJSON(id: optionID2.rawValue, label: "Second", position: 2),
        ].joined(separator: ",")
        await assertDefinitionMutationRejected(
            "option reorder order mismatch",
            request: reorderRequest,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "active",
                    revision: 2,
                    valueType: "select",
                    options: "[\(originalOrder)]",
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.optionReorder(endpoint, request)
            },
        )
    }

    func testOptionDisableRejectsResponsesOutsideRequestContext() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let optionID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let existingOptions = propertyOptionJSON(id: optionID.rawValue, label: "Existing", position: 1)
        let request = try PropertyOptionDisableRequest(
            propertyID: propertyID,
            optionID: optionID,
            expectedDefinitionRevision: 1,
            expectedOptions: [
                PropertyOption(id: optionID, label: "Existing", position: 1, state: .active),
            ],
        )

        await assertDefinitionMutationRejected(
            "option disable state mismatch",
            request: request,
            response: definitionResponse(
                definition: propertyDefinitionJSON(
                    propertyID: propertyID.rawValue,
                    state: "active",
                    revision: 2,
                    valueType: "select",
                    options: "[\(existingOptions)]",
                ),
            ),
            endpoint: endpoint,
            operation: { client, endpoint, request in
                try await client.optionDisable(endpoint, request)
            },
        )
    }
}

private struct QueryContextMismatchCase {
    let name: String
    let request: PropertyConditionQueryRequest
    let response: String
}

private struct AssignmentListContextCase {
    let name: String
    let request: PropertyAssignmentListRequest
    let response: String
}

private struct DefinitionListContextCase {
    let name: String
    let request: PropertyDefinitionListRequest
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

private func propertyAssignmentJSON(propertyID: String) -> String {
    """
    {
      "property_id":"\(propertyID)",
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "value_type":"text",
      "cardinality":"one",
      "state":"null",
      "revision":1
    }
    """
}

private func assignmentPageResponse(assignments: String) -> String {
    """
    {
      "request_id":"assignment-id",
      "ok":true,
      "result":{
        "assignments":\(assignments),
        "has_more":false
      }
    }
    """
}

private func definitionListContextCases(
    propertyID1: PropertyID,
    propertyID2: PropertyID,
) throws -> [DefinitionListContextCase] {
    let active1 = propertyDefinitionJSON(propertyID: propertyID1.rawValue, state: "active")
    let active2 = propertyDefinitionJSON(propertyID: propertyID2.rawValue, state: "active")
    let disabled1 = propertyDefinitionJSON(propertyID: propertyID1.rawValue, state: "disabled")
    return try [
        DefinitionListContextCase(
            name: "page contains too many definitions",
            request: PropertyDefinitionListRequest(
                pageSize: 1,
                requestedPropertyIDs: [propertyID1, propertyID2],
            ),
            response: definitionPageResponse(definitions: "[\(active1),\(active2)]"),
        ),
        DefinitionListContextCase(
            name: "page contains an unrequested property",
            request: PropertyDefinitionListRequest(
                pageSize: 2,
                requestedPropertyIDs: [propertyID1],
            ),
            response: definitionPageResponse(definitions: "[\(active2)]"),
        ),
        DefinitionListContextCase(
            name: "page contains disabled definition when excluded",
            request: PropertyDefinitionListRequest(
                pageSize: 2,
                includeDisabled: false,
            ),
            response: definitionPageResponse(definitions: "[\(disabled1)]"),
        ),
    ]
}

func propertyDefinitionJSON(
    propertyID: String,
    state: String,
    name: String = "Property name",
    revision: Int = 1,
    valueType: String = "text",
    cardinality: String = "one",
    options: String = "[]",
) -> String {
    let reason = state == "disabled" ? "definition_disabled" : "unsupported_value_contract"
    return """
    {
      "property_id":"\(propertyID)",
      "key":"property-key",
      "name":"\(name)",
      "value_type":"\(valueType)",
      "cardinality":"\(cardinality)",
      "state":"\(state)",
      "origin":"user_defined",
      "revision":\(revision),
      "options":\(options),
      "condition_capability":{
        "supported":false,
        "reason":"\(reason)"
      }
    }
    """
}

func propertyOptionJSON(id: String, label: String, position: Int, state: String = "active") -> String {
    """
    {
      "option_id":"\(id)",
      "label":"\(label)",
      "position":\(position),
      "state":"\(state)"
    }
    """
}

func definitionResponse(definition: String) -> String {
    """
    {
      "request_id":"definition-id",
      "ok":true,
      "result":{"definition":\(definition)}
    }
    """
}

func assertDefinitionMutationRejected<Request: Encodable & Sendable>(
    _ name: String,
    request: Request,
    response: String,
    endpoint: EntryCoreEndpoint,
    operation: @escaping @Sendable (
        EntryCorePropertyClient,
        EntryCoreEndpoint,
        Request,
    ) async throws -> PropertyDefinition,
) async {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "definition-id" },
        makeTransport: recorder.makeTransport,
    )

    do {
        _ = try await operation(client, endpoint, request)
        XCTFail("\(name) should be rejected")
    } catch {
        XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, name)
    }
    XCTAssertEqual(recorder.creationCount, 1, name)
    XCTAssertEqual(recorder.requests.count, 1, name)
}

private func definitionPageResponse(definitions: String) -> String {
    """
    {
      "request_id":"definition-id",
      "ok":true,
      "result":{
        "definitions":\(definitions),
        "has_more":false
      }
    }
    """
}

private func executeResponseCases(
    propertyID1: PropertyID,
    propertyID2: PropertyID,
    propertyID3: PropertyID,
) -> [(String, String)] {
    let assignment1 = propertyAssignmentJSON(propertyID: propertyID1.rawValue)
    let assignment2 = propertyAssignmentJSON(propertyID: propertyID2.rawValue)
    let assignment3 = propertyAssignmentJSON(propertyID: propertyID3.rawValue)
    return [
        (
            "fewer assignments",
            executeResponse(assignments: "[\(assignment1)]"),
        ),
        (
            "wrong assignment order",
            executeResponse(assignments: "[\(assignment2),\(assignment1)]"),
        ),
        (
            "unrequested property",
            executeResponse(assignments: "[\(assignment1),\(assignment3)]"),
        ),
    ]
}

private func executeResponse(assignments: String) -> String {
    """
    {
      "request_id":"execute-id",
      "ok":true,
      "result":{"assignments":\(assignments)}
    }
    """
}

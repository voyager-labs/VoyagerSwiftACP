import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

extension EntryCorePropertyClientFlowTests {
    func testPrepareRejectsResponseOutsideRequestChanges() async throws {
        let propertyID1 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let propertyID2 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000002")
        let propertyID3 = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000003")
        let change1 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID1,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
        )
        let change2 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/b"),
            propertyID: propertyID2,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
        )
        let request = try PropertyChangeRequest(changes: [change1, change2])
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        for (name, response) in prepareResponseCases(
            propertyID1: propertyID1,
            propertyID2: propertyID2,
            propertyID3: propertyID3,
        ) {
            await assertPrepareResponseRejected(name, request: request, response: response, endpoint: endpoint)
        }
    }

    func testExecuteRequiresStableTargetIdentityBeforeTransport() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let change = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
        )
        let request = try PropertyChangeRequest(changes: [change])
        let recorder =
            PropertyTransportRecorder(
                response: Data(#"{"request_id":"execute-id","ok":true,"result":{"assignments":[]}}"#
                    .utf8),
            )
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "execute-id" },
            makeTransport: recorder.makeTransport,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        do {
            _ = try await client.changeExecute(endpoint, request)
            XCTFail("missing target identity should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .localValidation)
        }
        XCTAssertEqual(recorder.creationCount, 0)
        XCTAssertEqual(recorder.requests.count, 0)
    }

    /// execute 응답 assignment는 요청 change로 완전히 결정된다: revision은
    /// expected + 1이고 state·payload는 desired를 반영해야 한다. identity만
    /// 일치하는 stale revision이나 다른 값 응답은 protocolMismatch로 거절한다.
    func testExecuteRejectsResponseViolatingRequestedChange() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let change = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 2,
            desired: .value(.text, .one, .text("after")),
            entryID: entryID,
        )
        let request = try PropertyChangeRequest(changes: [change])
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        for (name, assignmentJSON) in executeAssignmentMismatchCases(
            propertyID: propertyID.rawValue,
            entryID: entryID.rawValue,
        ) {
            let response = propertyChangeExecuteResponse(assignments: "[\(assignmentJSON)]")
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

        let accepted = propertyChangeAssignmentJSON(
            propertyID: propertyID.rawValue,
            entryID: entryID.rawValue,
            revision: 3,
        )
        let acceptedRecorder = PropertyTransportRecorder(
            response: Data(
                propertyChangeExecuteResponse(assignments: "[\(accepted)]").utf8,
            ),
        )
        let acceptedClient = EntryCorePropertyClient.makeLive(
            requestID: { "execute-id" },
            makeTransport: acceptedRecorder.makeTransport,
        )
        _ = try await acceptedClient.changeExecute(endpoint, request)
        XCTAssertEqual(acceptedRecorder.requests.count, 1)
    }

    /// 생성 응답은 항상 user-defined origin이어야 한다. built-in origin은
    /// 요청으로 만들 수 없는 ownership이므로 protocolMismatch로 거절한다.
    func testDefinitionCreateRejectsBuiltInOriginResponse() async throws {
        let request = try PropertyDefinitionCreateRequest(
            key: "created-key",
            name: "created name",
            valueType: .text,
            cardinality: .one,
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let runtimeUnavailable = #"{"supported":false,"reason":"source_runtime_unavailable"}"#
        let supported = """
        {"supported":true,"evaluation_scope":"local_assignment","catalog_version":"2.2.0",
        "native_type":"string","allowed_operators":["all","any","cn","empty","eq","ew","exists","nc","neq","rx","sw"]}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        // decoder 관점에서는 유효한 페어링(built-in + runtime-unavailable)이라도
        // create 응답으로는 승인되지 않는다.
        let recorder = PropertyTransportRecorder(
            response: Data(definitionCreateResponse(origin: "built_in", capability: runtimeUnavailable).utf8),
        )
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "create-id" },
            makeTransport: recorder.makeTransport,
        )

        do {
            _ = try await client.definitionCreate(endpoint, request)
            XCTFail("built-in origin create response should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(recorder.requests.count, 1)

        let acceptedRecorder = PropertyTransportRecorder(
            response: Data(definitionCreateResponse(origin: "user_defined", capability: supported).utf8),
        )
        let acceptedClient = EntryCorePropertyClient.makeLive(
            requestID: { "create-id" },
            makeTransport: acceptedRecorder.makeTransport,
        )
        let created = try await acceptedClient.definitionCreate(endpoint, request)
        XCTAssertEqual(created.origin, .userDefined)
    }

    /// update/disable/option mutation 응답도 user-defined origin이어야 한다.
    /// mutateDefinition은 Voyager-issued 정의만 대상으로 하므로 built-in
    /// origin mutation 결과는 존재할 수 없다.
    func testDefinitionUpdateRejectsBuiltInOriginResponse() async throws {
        let propertyID = "00000000-0000-0000-8000-000000000001"
        let request = try PropertyDefinitionUpdateRequest(
            propertyID: PropertyID(rawValue: propertyID),
            expectedDefinitionRevision: 1,
            name: "updated name",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        func updateResponse(origin: String, capability: String) -> String {
            """
            {
              "request_id":"update-id",
              "ok":true,
              "result":{"definition":{
                "property_id":"\(propertyID)",
                "key":"created-key","name":"updated name",
                "value_type":"text","cardinality":"one","state":"active","origin":"\(origin)",
                "revision":2,"options":[],
                "condition_capability":\(capability)
              }}
            }
            """
        }
        let runtimeUnavailable = #"{"supported":false,"reason":"source_runtime_unavailable"}"#
        let supported = """
        {"supported":true,"evaluation_scope":"local_assignment","catalog_version":"2.2.0",
        "native_type":"string","allowed_operators":["all","any","cn","empty","eq","ew","exists","nc","neq","rx","sw"]}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        // decoder 관점에서 유효한 built-in 페어링도 mutation 응답으로는 승인되지 않는다.
        let recorder = PropertyTransportRecorder(
            response: Data(updateResponse(origin: "built_in", capability: runtimeUnavailable).utf8),
        )
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "update-id" },
            makeTransport: recorder.makeTransport,
        )
        do {
            _ = try await client.definitionUpdate(endpoint, request)
            XCTFail("built-in origin update response should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(recorder.requests.count, 1)

        let acceptedRecorder = PropertyTransportRecorder(
            response: Data(updateResponse(origin: "user_defined", capability: supported).utf8),
        )
        let acceptedClient = EntryCorePropertyClient.makeLive(
            requestID: { "update-id" },
            makeTransport: acceptedRecorder.makeTransport,
        )
        let updated = try await acceptedClient.definitionUpdate(endpoint, request)
        XCTAssertEqual(updated.origin, .userDefined)
    }

    /// CreateOption은 새 option을 항상 마지막 ordinal 뒤에 추가한다. 기존
    /// option이 같은 label을 가질 때 마지막 option이 아니면 누락·치환 응답이다.
    func testOptionCreateRejectsResponseWithoutRequestedLastOption() async throws {
        let request = try PropertyOptionCreateRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            expectedDefinitionRevision: 1,
            label: "new-label",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")

        let replacedRecorder = PropertyTransportRecorder(
            response: Data(optionCreateResponse(lastLabel: "other-label", operators: operators).utf8),
        )
        let replacedClient = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: replacedRecorder.makeTransport,
        )
        do {
            _ = try await replacedClient.optionCreate(endpoint, request)
            XCTFail("response without the requested option last should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(replacedRecorder.requests.count, 1)

        let createdRecorder = PropertyTransportRecorder(
            response: Data(optionCreateResponse(lastLabel: "new-label", operators: operators).utf8),
        )
        let createdClient = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: createdRecorder.makeTransport,
        )
        let created = try await createdClient.optionCreate(endpoint, request)
        XCTAssertEqual(created.options.last?.label, "new-label")
    }
}

private func definitionCreateResponse(origin: String, capability: String) -> String {
    """
    {
      "request_id":"create-id",
      "ok":true,
      "result":{"definition":{
        "property_id":"00000000-0000-0000-8000-000000000001",
        "key":"created-key","name":"created name",
        "value_type":"text","cardinality":"one","state":"active","origin":"\(origin)",
        "revision":1,"options":[],
        "condition_capability":\(capability)
      }}
    }
    """
}

private func executeAssignmentMismatchCases(
    propertyID: String,
    entryID: String,
) -> [(String, String)] {
    [
        ("stale revision", propertyChangeAssignmentJSON(propertyID: propertyID, entryID: entryID, revision: 2)),
        (
            "wrong state",
            """
            {
              "property_id":"\(propertyID)",
              "entry_id":"\(entryID)",
              "value_type":"text","cardinality":"one","state":"null","revision":3
            }
            """,
        ),
        (
            "wrong value",
            propertyChangeAssignmentJSON(propertyID: propertyID, entryID: entryID, revision: 3, value: "other"),
        ),
    ]
}

private func propertyChangeAssignmentJSON(
    propertyID: String,
    entryID: String,
    revision: Int64,
    value: String = "after",
) -> String {
    """
    {
      "property_id":"\(propertyID)",
      "entry_id":"\(entryID)",
      "value_type":"text","cardinality":"one","state":"value","revision":\(revision),
      "value":"\(value)"
    }
    """
}

private func propertyChangeExecuteResponse(assignments: String) -> String {
    """
    {
      "request_id":"execute-id",
      "ok":true,
      "result":{"assignments":\(assignments)}
    }
    """
}

private func optionCreateResponse(lastLabel: String, operators: String) -> String {
    """
    {
      "request_id":"option-create-id",
      "ok":true,
      "result":{"definition":{
        "property_id":"00000000-0000-0000-8000-000000000001",
        "key":"select-key","name":"select name",
        "value_type":"select","cardinality":"one","state":"active","origin":"user_defined",
        "revision":2,
        "options":[
          {"option_id":"00000000-0000-7000-8000-000000000001","label":"other-label","position":1,"state":"active"},
          {"option_id":"00000000-0000-7000-8000-000000000002","label":"\(lastLabel)","position":2,"state":"active"}
        ],
        "condition_capability":{"supported":true,"evaluation_scope":"local_assignment",
          "catalog_version":"2.2.0","native_type":"categorical","allowed_operators":[\(operators)]}
      }}
    }
    """
}

private func prepareResponseCases(
    propertyID1: PropertyID,
    propertyID2: PropertyID,
    propertyID3: PropertyID,
) -> [(String, String)] {
    let first = propertyChangePreparedJSON(propertyID: propertyID1.rawValue, target: "/a")
    let second = propertyChangePreparedJSON(propertyID: propertyID2.rawValue, target: "/b")
    let wrongTarget = propertyChangePreparedJSON(propertyID: propertyID1.rawValue, target: "/wrong")
    let wrongProperty = propertyChangePreparedJSON(propertyID: propertyID3.rawValue, target: "/a")
    let wrongDesired = propertyChangePreparedJSON(
        propertyID: propertyID1.rawValue,
        target: "/a",
        afterState: "unknown",
    )
    return [
        (
            "fewer changes",
            propertyChangePrepareResponse(changes: "[\(first)]"),
        ),
        (
            "wrong change order",
            propertyChangePrepareResponse(changes: "[\(second),\(first)]"),
        ),
        (
            "wrong target",
            propertyChangePrepareResponse(changes: "[\(wrongTarget),\(second)]"),
        ),
        (
            "wrong property",
            propertyChangePrepareResponse(changes: "[\(wrongProperty),\(second)]"),
        ),
        (
            "wrong desired state",
            propertyChangePrepareResponse(changes: "[\(wrongDesired),\(second)]"),
        ),
    ]
}

private func propertyChangePreparedJSON(
    propertyID: String,
    target: String,
    afterState: String = "null",
) -> String {
    """
    {
      "target":{"kind":"local_path","local_path":"\(target)"},
      "property_id":"\(propertyID)",
      "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "before":null,
      "after":{"state":"\(afterState)"}
    }
    """
}

private func propertyChangePrepareResponse(changes: String) -> String {
    """
    {
      "request_id":"prepare-id",
      "ok":true,
      "result":{"changes":\(changes),"requires_confirmation":true}
    }
    """
}

private func assertPrepareResponseRejected(
    _ name: String,
    request: PropertyChangeRequest,
    response: String,
    endpoint: EntryCoreEndpoint,
) async {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "prepare-id" },
        makeTransport: recorder.makeTransport,
    )

    do {
        _ = try await client.changePrepare(endpoint, request)
        XCTFail("\(name) should be rejected")
    } catch {
        XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, name)
    }
    XCTAssertEqual(recorder.creationCount, 1, name)
    XCTAssertEqual(recorder.requests.count, 1, name)
}

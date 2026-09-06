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
            expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
        )
        let change2 = try PropertyChangeTarget(
            target: PropertyTarget(localPath: "/b"),
            propertyID: propertyID2,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: 0,
            desired: .null,
            expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
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
            expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
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
            expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
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

    /// update/disable/option mutation 응답은 voyager_issued scheme이어야 한다.
    /// Go mutateDefinition과 동일하게 mutation 가능 여부는 origin이 아니라
    /// identity scheme이 결정하므로 registry-derived scheme mutation 결과는
    /// 존재할 수 없다.
    func testDefinitionUpdateRejectsRegistryDerivedSchemeResponse() async throws {
        let propertyID = "00000000-0000-0000-8000-000000000001"
        let request = try PropertyDefinitionUpdateRequest(
            propertyID: PropertyID(rawValue: propertyID),
            expectedDefinitionRevision: 1,
            expectedDefinition: PropertyDefinition(
                id: PropertyID(rawValue: propertyID),
                key: "created-key",
                name: "created name",
                valueType: .text,
                cardinality: .one,
                state: .active,
                origin: .userDefined,
                identityScheme: .voyagerIssued,
                editable: true,
                revision: 1,
                options: [],
                conditionCapability: .supported(
                    catalogVersion: PropertyConditionCatalog.version,
                    nativeType: .string,
                    allowedOperators: PropertyConditionRelation.operators(for: .string),
                ),
            ),
            name: "updated name",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        func updateResponse(identityScheme: String, editable: Bool, capability: String) -> String {
            """
            {
              "request_id":"update-id",
              "ok":true,
              "result":{"definition":{
                "property_id":"\(propertyID)",
                "key":"created-key","name":"updated name",
                "value_type":"text","cardinality":"one","state":"active",
                "origin":"user_defined","identity_scheme":"\(identityScheme)","editable":\(editable),
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

        // decoder 관점에서 유효한 registry-derived 페어링도 mutation 응답으로는
        // 승인되지 않는다.
        let recorder = PropertyTransportRecorder(
            response: Data(
                updateResponse(identityScheme: "registry_derived", editable: false, capability: runtimeUnavailable)
                    .utf8,
            ),
        )
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "update-id" },
            makeTransport: recorder.makeTransport,
        )
        do {
            _ = try await client.definitionUpdate(endpoint, request)
            XCTFail("registry-derived scheme update response should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(recorder.requests.count, 1)

        let acceptedRecorder = PropertyTransportRecorder(
            response: Data(
                updateResponse(identityScheme: "voyager_issued", editable: true, capability: supported).utf8,
            ),
        )
        let acceptedClient = EntryCorePropertyClient.makeLive(
            requestID: { "update-id" },
            makeTransport: acceptedRecorder.makeTransport,
        )
        let updated = try await acceptedClient.definitionUpdate(endpoint, request)
        XCTAssertEqual(updated.identityScheme, .voyagerIssued)
    }

    /// 프리셋 정의(built_in origin + voyager_issued + editable)는 option
    /// mutation의 정상 대상이다. 선택지 없이 생성되는 Project 프리셋의 첫
    /// 선택지 추가가 의도된 property.option.create 경로로 가능해야 한다.
    func testOptionCreateAcceptsVoyagerIssuedPresetDefinition() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let optionID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let request = try PropertyOptionCreateRequest(
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedDefinition: PropertyDefinition(
                id: propertyID,
                key: "project",
                name: "Project",
                valueType: .select,
                cardinality: .one,
                state: .active,
                origin: .builtIn,
                identityScheme: .voyagerIssued,
                editable: true,
                revision: 1,
                options: [],
                conditionCapability: .unsupported(.sourceRuntimeUnavailable),
            ),
            label: "new-label",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let recorder = PropertyTransportRecorder(
            response: Data(presetOptionCreateResponse(optionID: optionID.rawValue).utf8),
        )
        let client = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: recorder.makeTransport,
        )

        let created = try await client.optionCreate(endpoint, request)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(created.origin, .builtIn)
        XCTAssertEqual(created.identityScheme, .voyagerIssued)
        XCTAssertEqual(created.options.last?.label, "new-label")
    }

    /// CreateOption은 새 option을 항상 마지막 ordinal 뒤에 추가한다. 기존
    /// option이 같은 label을 가질 때 마지막 option이 아니면 누락·치환 응답이다.
    func testOptionCreateRejectsResponseWithoutRequestedLastOption() async throws {
        let request = try optionCreateRequest(
            expectedOptions: [
                PropertyOption(
                    id: PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001"),
                    label: "other-label",
                    position: 1,
                    state: .active,
                ),
            ],
            label: "new-label",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")

        let replacedRecorder = PropertyTransportRecorder(
            response: Data(twoOptionCreateResponse(lastLabel: "other-label", operators: operators).utf8),
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
            response: Data(twoOptionCreateResponse(lastLabel: "new-label", operators: operators).utf8),
        )
        let createdClient = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: createdRecorder.makeTransport,
        )
        let created = try await createdClient.optionCreate(endpoint, request)
        XCTAssertEqual(created.options.last?.label, "new-label")
    }

    /// 기존 마지막 option이 이미 같은 label을 가지면 option 추가 없이
    /// revision만 올린 응답도 max(position)·label 대조를 통과한다. 사전
    /// option IDs 대조는 이 누락 생성을 거절한다.
    func testOptionCreateRejectsResponseWithoutNewOption() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let request = try optionCreateRequest(
            expectedOptions: [
                PropertyOption(id: option1ID, label: "new-label", position: 1, state: .active),
            ],
            label: "new-label",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")

        let noAdditionRecorder = PropertyTransportRecorder(
            response: Data(
                optionCreateResponse(
                    options: selectOptionJSON(id: option1ID.rawValue, label: "new-label", position: 1),
                    operators: operators,
                ).utf8,
            ),
        )
        let noAdditionClient = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: noAdditionRecorder.makeTransport,
        )
        do {
            _ = try await noAdditionClient.optionCreate(endpoint, request)
            XCTFail("response without a new option should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(noAdditionRecorder.requests.count, 1)
    }

    /// CreateOption은 기존 option을 수정하지 않는다. 사전 snapshot과 다른
    /// label·state·position을 가진 선행 option이 오면 새 option이 올바르더라도
    /// 거절된다.
    func testOptionCreateRejectsDriftedPreMutationOptions() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let option2ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let request = try PropertyOptionCreateRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            expectedDefinitionRevision: 1,
            expectedDefinition: PropertyDefinition(
                id: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
                key: "select-key",
                name: "select name",
                valueType: .select,
                cardinality: .one,
                state: .active,
                origin: .userDefined,
                identityScheme: .voyagerIssued,
                editable: true,
                revision: 1,
                options: [
                    PropertyOption(id: option1ID, label: "original-label", position: 1, state: .active),
                ],
                conditionCapability: .supported(
                    catalogVersion: PropertyConditionCatalog.version,
                    nativeType: .categorical,
                    allowedOperators: PropertyConditionRelation.operators(for: .categorical),
                ),
            ),
            label: "new-label",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")

        let driftedRecorder = PropertyTransportRecorder(
            response: Data(
                optionCreateResponse(
                    options: [
                        selectOptionJSON(id: option1ID.rawValue, label: "changed-label", position: 1),
                        selectOptionJSON(id: option2ID.rawValue, label: "new-label", position: 2),
                    ].joined(separator: ",\n          "),
                    operators: operators,
                ).utf8,
            ),
        )
        let driftedClient = EntryCorePropertyClient.makeLive(
            requestID: { "option-create-id" },
            makeTransport: driftedRecorder.makeTransport,
        )
        do {
            _ = try await driftedClient.optionCreate(endpoint, request)
            XCTFail("drifted pre-mutation option should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(driftedRecorder.requests.count, 1)
    }

    /// RenameOption은 활성 대상 option만 수정한다. snapshot에 대상이 없으면
    /// mutation 응답 자체가 불가능하므로 revision만 올린 응답도 거절된다.
    func testOptionUpdateRejectsMissingTargetOption() async throws {
        let option2ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let request = try PropertyOptionUpdateRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            optionID: PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001"),
            expectedDefinitionRevision: 1,
            expectedDefinition: selectDefinitionSnapshot(options: [
                PropertyOption(id: option2ID, label: "Second", position: 1, state: .active),
            ]),
            label: "Renamed option",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")
        let response = optionCreateResponse(
            options: [
                selectOptionJSON(id: option2ID.rawValue, label: "Second", position: 1),
            ].joined(separator: ",\n          "),
            operators: operators,
        )

        await assertOptionMutationRejected(
            name: "update with missing target option",
            response: response,
            endpoint: endpoint,
        ) { client, endpoint in
            try await client.optionUpdate(endpoint, request)
        }
    }

    /// DisableOption은 활성 대상 option만 비활성화한다. 이미 비활성인 option에
    /// 대한 응답은 정상 daemon에서 생성될 수 없다.
    func testOptionDisableRejectsInactiveTargetOption() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let request = try PropertyOptionDisableRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            optionID: option1ID,
            expectedDefinitionRevision: 1,
            expectedDefinition: selectDefinitionSnapshot(options: [
                PropertyOption(id: option1ID, label: "First", position: 1, state: .disabled),
            ]),
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")
        let response = optionCreateResponse(
            options: [
                selectOptionJSON(
                    id: option1ID.rawValue, label: "First", position: 1, state: "disabled",
                ),
            ].joined(separator: ",\n          "),
            operators: operators,
        )

        await assertOptionMutationRejected(
            name: "disable with inactive target option",
            response: response,
            endpoint: endpoint,
        ) { client, endpoint in
            try await client.optionDisable(endpoint, request)
        }
    }

    /// prepare의 before는 요청 CAS 기준을 그대로 반영해야 한다: expected 0이면
    /// nil, 양수면 같은 revision. 그렇지 않으면 caller가 실제 CAS 기준과 다른
    /// 이전 값을 확인한 뒤 mutation을 승인하게 된다.
    func testPrepareRejectsBeforeViolatingExpectedRevision() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")

        let cases = try [
            PrepareCASCase(
                name: "expected 0 with non-nil before",
                request: prepareCASRequest(propertyID: propertyID, entryID: entryID, expectedAssignmentRevision: 0),
                response: prepareCASResponse(propertyID: propertyID, entryID: entryID, beforeRevision: 0),
            ),
            PrepareCASCase(
                name: "expected 2 with nil before",
                request: prepareCASRequest(propertyID: propertyID, entryID: entryID, expectedAssignmentRevision: 2),
                response: prepareCASResponse(propertyID: propertyID, entryID: entryID, beforeRevision: nil),
            ),
            PrepareCASCase(
                name: "expected 2 with revision 3 before",
                request: prepareCASRequest(propertyID: propertyID, entryID: entryID, expectedAssignmentRevision: 2),
                response: prepareCASResponse(propertyID: propertyID, entryID: entryID, beforeRevision: 3),
            ),
        ]
        for prepareCase in cases {
            let recorder = PropertyTransportRecorder(response: Data(prepareCase.response.utf8))
            let client = EntryCorePropertyClient.makeLive(
                requestID: { "prepare-id" },
                makeTransport: recorder.makeTransport,
            )

            do {
                _ = try await client.changePrepare(endpoint, prepareCase.request)
                XCTFail("\(prepareCase.name) should be rejected")
            } catch {
                XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, prepareCase.name)
            }
            XCTAssertEqual(recorder.requests.count, 1, prepareCase.name)
        }

        let matchingRecorder = try PropertyTransportRecorder(
            response: Data(
                prepareCASResponse(propertyID: propertyID, entryID: entryID, beforeRevision: 2).utf8,
            ),
        )
        let matchingClient = EntryCorePropertyClient.makeLive(
            requestID: { "prepare-id" },
            makeTransport: matchingRecorder.makeTransport,
        )
        _ = try await matchingClient.changePrepare(
            endpoint,
            prepareCASRequest(propertyID: propertyID, entryID: entryID, expectedAssignmentRevision: 2),
        )
        XCTAssertEqual(matchingRecorder.requests.count, 1)
    }

    /// .value 변경의 prepare에서 before revision이 같아도 요청 desired와 다른
    /// type·cardinality의 before는 다른 CAS 기준이다.
    func testPrepareRejectsBeforeViolatingRequestedValueContract() async throws {
        let propertyID = try PropertyID(rawValue: "00000000-0000-0000-8000-000000000001")
        let entryID = try EntryCoreEntryID(rawValue: "ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let request = try PropertyChangeRequest(changes: [
            PropertyChangeTarget(
                target: PropertyTarget(localPath: "/a"),
                propertyID: propertyID,
                expectedDefinitionRevision: 1,
                expectedAssignmentRevision: 2,
                desired: .value(.text, .one, .text("v")),
                expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
                entryID: entryID,
            ),
        ])

        let mismatchedRecorder = PropertyTransportRecorder(
            response: Data(prepareValueContractResponse(beforeValueType: "number").utf8),
        )
        let mismatchedClient = EntryCorePropertyClient.makeLive(
            requestID: { "prepare-id" },
            makeTransport: mismatchedRecorder.makeTransport,
        )
        do {
            _ = try await mismatchedClient.changePrepare(endpoint, request)
            XCTFail("before with a different value type should be rejected")
        } catch {
            XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch)
        }
        XCTAssertEqual(mismatchedRecorder.requests.count, 1)

        let matchingRecorder = PropertyTransportRecorder(
            response: Data(prepareValueContractResponse(beforeValueType: "text").utf8),
        )
        let matchingClient = EntryCorePropertyClient.makeLive(
            requestID: { "prepare-id" },
            makeTransport: matchingRecorder.makeTransport,
        )
        _ = try await matchingClient.changePrepare(endpoint, request)
        XCTAssertEqual(matchingRecorder.requests.count, 1)
    }
}

/// .value 변경의 prepare에서 before는 요청 desired와 같은 type·cardinality의
/// 같은 revision이어야 한다.
private func prepareValueContractResponse(beforeValueType: String) -> String {
    """
    {
      "request_id":"prepare-id",
      "ok":true,
      "result":{"changes":[{
        "target":{"kind":"local_path","local_path":"/a"},
        "property_id":"00000000-0000-0000-8000-000000000001",
        "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "before":{"property_id":"00000000-0000-0000-8000-000000000001",
          "entry_id":"ent:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","value_type":"\(beforeValueType)",
          "cardinality":"one","state":"null","revision":2},
        "after":{"state":"value","value_type":"text","cardinality":"one","value":"v"}
      }],"requires_confirmation":true}
    }
    """
}

private struct PrepareCASCase {
    let name: String
    let request: PropertyChangeRequest
    let response: String
}

private func prepareCASRequest(
    propertyID: PropertyID,
    entryID: EntryCoreEntryID,
    expectedAssignmentRevision: Int64,
) throws -> PropertyChangeRequest {
    try PropertyChangeRequest(changes: [
        PropertyChangeTarget(
            target: PropertyTarget(localPath: "/a"),
            propertyID: propertyID,
            expectedDefinitionRevision: 1,
            expectedAssignmentRevision: expectedAssignmentRevision,
            desired: .null,
            expectedValueContract: ExpectedValueContract(valueType: .text, cardinality: .one),
            entryID: entryID,
        ),
    ])
}

private func prepareCASResponse(
    propertyID: PropertyID,
    entryID: EntryCoreEntryID,
    beforeRevision: Int64?,
) throws -> String {
    let before = if let beforeRevision {
        """
        "before":{"property_id":"\(propertyID.rawValue)","entry_id":"\(entryID
            .rawValue)","value_type":"text","cardinality":"one","state":"null","revision":\(beforeRevision)},
        """
    } else {
        "\"before\":null,"
    }
    return """
    {
      "request_id":"prepare-id",
      "ok":true,
      "result":{"changes":[{
        "target":{"kind":"local_path","local_path":"/a"},
        "property_id":"\(propertyID.rawValue)",
        "entry_id":"\(entryID.rawValue)",
        \(before)
        "after":{"state":"null"}
      }],"requires_confirmation":true}
    }
    """
}

private func definitionCreateResponse(origin: String, capability: String) -> String {
    """
    {
      "request_id":"create-id",
      "ok":true,
      "result":{"definition":{
        "property_id":"00000000-0000-0000-8000-000000000001",
        "key":"created-key","name":"created name",
        "value_type":"text","cardinality":"one","state":"active","origin":"\(
            origin
        )","identity_scheme":"voyager_issued","editable":true,
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

private func twoOptionCreateResponse(lastLabel: String, operators: String) -> String {
    optionCreateResponse(
        options: [
            selectOptionJSON(id: "00000000-0000-7000-8000-000000000001", label: "other-label", position: 1),
            selectOptionJSON(id: "00000000-0000-7000-8000-000000000002", label: lastLabel, position: 2),
        ].joined(separator: ",\n          "),
        operators: operators,
    )
}

private func optionCreateRequest(
    expectedOptions: [PropertyOption],
    label: String,
) throws -> PropertyOptionCreateRequest {
    try PropertyOptionCreateRequest(
        propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
        expectedDefinitionRevision: 1,
        expectedDefinition: selectDefinitionSnapshot(options: expectedOptions),
        label: label,
    )
}

func selectOptionJSON(id: String, label: String, position: Int, state: String = "active") -> String {
    """
    {"option_id":"\(id)","label":"\(label)","position":\(position),"state":"\(state)"}
    """
}

func optionCreateResponse(options: String, operators: String) -> String {
    """
    {
      "request_id":"option-create-id",
      "ok":true,
      "result":{"definition":{
        "property_id":"00000000-0000-0000-8000-000000000001",
        "key":"select-key","name":"select name",
        "value_type":"select","cardinality":"one","state":"active","origin":"user_defined","identity_scheme":"voyager_issued","editable":true,
        "revision":2,
        "options":[
          \(options)
        ],
        "condition_capability":{"supported":true,"evaluation_scope":"local_assignment",
          "catalog_version":"2.2.0","native_type":"categorical","allowed_operators":[\(operators)]}
      }}
    }
    """
}

/// 프리셋 정의의 option create 응답이다. built_in origin + voyager_issued +
/// editable 페어링과 built-in 정의의 runtime-unavailable capability를 운반한다.
func presetOptionCreateResponse(optionID: String) -> String {
    """
    {
      "request_id":"option-create-id",
      "ok":true,
      "result":{"definition":{
        "property_id":"00000000-0000-0000-8000-000000000001",
        "key":"project","name":"Project",
        "value_type":"select","cardinality":"one","state":"active","origin":"built_in","identity_scheme":"voyager_issued","editable":true,
        "revision":2,
        "options":[
          {"option_id":"\(optionID)","label":"new-label","position":1,"state":"active"}
        ],
        "condition_capability":{"supported":false,"reason":"source_runtime_unavailable"}
      }}
    }
    """
}

func assertOptionCreateLabelMismatchRejected(
    request: PropertyOptionCreateRequest,
    existingOptions: String,
    wrongNewOption: String,
    propertyID: String,
    endpoint: EntryCoreEndpoint,
) async {
    await assertDefinitionMutationRejected(
        "option create missing requested label",
        request: request,
        response: definitionResponse(
            definition: propertyDefinitionJSON(
                propertyID: propertyID,
                state: "active",
                revision: 2,
                valueType: "select",
                options: "[\(existingOptions),\n          \(wrongNewOption)]",
            ),
        ),
        endpoint: endpoint,
        operation: { client, endpoint, request in
            try await client.optionCreate(endpoint, request)
        },
    )
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

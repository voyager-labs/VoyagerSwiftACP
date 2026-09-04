import Foundation
@testable import VoyagerEntryCoreClient
import XCTest

/// option mutation 응답이 사전 option snapshot에서 operation이 허용한 delta만
/// 반영하는지 검증한다. CreateOption·RenameOption·ReorderOptions·
/// DisableOption은 기존 option을 수정하지 않는다.
extension EntryCorePropertyClientFlowTests {
    /// RenameOption은 대상 label만 바꾼다. 다른 option의 label 변경이 섞인
    /// 응답은 정상 daemon에서 생성될 수 없다.
    func testOptionUpdateRejectsDriftedOtherOptions() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let option2ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let request = try PropertyOptionUpdateRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            optionID: option1ID,
            expectedDefinitionRevision: 1,
            expectedDefinition: selectDefinitionSnapshot(options: [
                PropertyOption(id: option1ID, label: "First", position: 1, state: .active),
                PropertyOption(id: option2ID, label: "Second", position: 2, state: .active),
            ]),
            label: "Renamed option",
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")
        let response = optionCreateResponse(
            options: [
                selectOptionJSON(id: option1ID.rawValue, label: "Renamed option", position: 1),
                selectOptionJSON(id: option2ID.rawValue, label: "Drifted", position: 2),
            ].joined(separator: ",\n          "),
            operators: operators,
        )

        await assertOptionMutationRejected(
            name: "update with drifted other option",
            response: response,
            endpoint: endpoint,
        ) { client, endpoint in
            try await client.optionUpdate(endpoint, request)
        }
    }

    /// ReorderOptions는 활성 순서만 바꾼다. 순서는 맞지만 다른 option의
    /// label이 바뀐 응답은 정상 daemon에서 생성될 수 없다.
    func testOptionReorderRejectsDriftedOtherOptions() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let option2ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let request = try PropertyOptionReorderRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            expectedDefinitionRevision: 1,
            optionIDs: [option2ID, option1ID],
            expectedDefinition: selectDefinitionSnapshot(options: [
                PropertyOption(id: option1ID, label: "First", position: 1, state: .active),
                PropertyOption(id: option2ID, label: "Second", position: 2, state: .active),
            ]),
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")
        let response = optionCreateResponse(
            options: [
                selectOptionJSON(id: option2ID.rawValue, label: "Second", position: 1),
                selectOptionJSON(id: option1ID.rawValue, label: "Drifted", position: 2),
            ].joined(separator: ",\n          "),
            operators: operators,
        )

        await assertOptionMutationRejected(
            name: "reorder with drifted other option",
            response: response,
            endpoint: endpoint,
        ) { client, endpoint in
            try await client.optionReorder(endpoint, request)
        }
    }

    /// DisableOption은 대상 상태만 바꾼다. 다른 option의 label 변경이 섞인
    /// 응답은 정상 daemon에서 생성될 수 없다.
    func testOptionDisableRejectsDriftedOtherOptions() async throws {
        let option1ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000001")
        let option2ID = try PropertyOptionID(rawValue: "00000000-0000-7000-8000-000000000002")
        let request = try PropertyOptionDisableRequest(
            propertyID: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
            optionID: option1ID,
            expectedDefinitionRevision: 1,
            expectedDefinition: selectDefinitionSnapshot(options: [
                PropertyOption(id: option1ID, label: "First", position: 1, state: .active),
                PropertyOption(id: option2ID, label: "Second", position: 2, state: .active),
            ]),
        )
        let endpoint = try EntryCoreEndpoint(path: "/tmp/property-client.sock")
        let operators = PropertyConditionRelation.operators(for: .categorical)
            .map { "\"\($0.rawValue)\"" }
            .joined(separator: ",")
        let response = optionCreateResponse(
            options: [
                selectOptionJSON(id: option1ID.rawValue, label: "First", position: 1, state: "disabled"),
                selectOptionJSON(id: option2ID.rawValue, label: "Drifted", position: 2),
            ].joined(separator: ",\n          "),
            operators: operators,
        )

        await assertOptionMutationRejected(
            name: "disable with drifted other option",
            response: response,
            endpoint: endpoint,
        ) { client, endpoint in
            try await client.optionDisable(endpoint, request)
        }
    }
}

func selectDefinitionSnapshot(options: [PropertyOption]) throws -> PropertyDefinition {
    try PropertyDefinition(
        id: PropertyID(rawValue: "00000000-0000-0000-8000-000000000001"),
        key: "select-key",
        name: "select name",
        valueType: .select,
        cardinality: .one,
        state: .active,
        origin: .userDefined,
        revision: 1,
        options: options,
        conditionCapability: .supported(
            catalogVersion: PropertyConditionCatalog.version,
            nativeType: .categorical,
            allowedOperators: PropertyConditionRelation.operators(for: .categorical),
        ),
    )
}

func assertOptionMutationRejected(
    name: String,
    response: String,
    endpoint: EntryCoreEndpoint,
    operation: @escaping @Sendable (EntryCorePropertyClient, EntryCoreEndpoint) async throws
        -> PropertyDefinition,
) async {
    let recorder = PropertyTransportRecorder(response: Data(response.utf8))
    let client = EntryCorePropertyClient.makeLive(
        requestID: { "option-create-id" },
        makeTransport: recorder.makeTransport,
    )
    do {
        _ = try await operation(client, endpoint)
        XCTFail("\(name) should be rejected")
    } catch {
        XCTAssertEqual(error as? EntryCoreClientError, .protocolMismatch, name)
    }
    XCTAssertEqual(recorder.requests.count, 1, name)
}

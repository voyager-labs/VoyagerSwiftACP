import Foundation

nonisolated public struct PropertyOptionCreateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    /// CreateOption은 기존 option을 수정하지 않고 새 option 하나만 마지막에
    /// 추가한다. 응답 definition이 이 사전 snapshot에서 option 추가·revision
    /// 증가 외에는 변하지 않는지 검증하는 데 쓰이며 wire 요청에는 포함되지
    /// 않는다.
    let expectedDefinition: PropertyDefinition
    let label: String
    public init(
        propertyID: PropertyID,
        expectedDefinitionRevision: Int64,
        expectedDefinition: PropertyDefinition,
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              expectedDefinition.id == propertyID,
              expectedDefinition.revision == expectedDefinitionRevision,
              expectedDefinition.state == .active,
              expectedDefinition.origin == .userDefined,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedDefinition = expectedDefinition
        self.label = label
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", expectedDefinitionRevision = "expected_definition_revision", label
    }
}

nonisolated public struct PropertyOptionUpdateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let optionID: PropertyOptionID
    let expectedDefinitionRevision: Int64
    /// RenameOption은 대상 label만 바꾼다. 응답 definition이 이 사전
    /// snapshot에서 대상 label 변경·revision 증가 외에는 변하지 않는지 검증하는
    /// 데 쓰이며 wire 요청에는 포함되지 않는다.
    let expectedDefinition: PropertyDefinition
    let label: String
    public init(
        propertyID: PropertyID,
        optionID: PropertyOptionID,
        expectedDefinitionRevision: Int64,
        expectedDefinition: PropertyDefinition,
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              expectedDefinition.id == propertyID,
              expectedDefinition.revision == expectedDefinitionRevision,
              expectedDefinition.state == .active,
              expectedDefinition.origin == .userDefined,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.optionID = optionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedDefinition = expectedDefinition
        self.label = label
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", optionID = "option_id",
           expectedDefinitionRevision = "expected_definition_revision",
           label
    }
}

nonisolated public struct PropertyOptionDisableRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let optionID: PropertyOptionID
    let expectedDefinitionRevision: Int64
    /// DisableOption은 대상 option의 상태만 비활성으로 바꾼다. 응답
    /// definition이 이 사전 snapshot에서 대상 상태 변경·revision 증가 외에는
    /// 변하지 않는지 검증하는 데 쓰이며 wire 요청에는 포함되지 않는다.
    let expectedDefinition: PropertyDefinition
    public init(
        propertyID: PropertyID,
        optionID: PropertyOptionID,
        expectedDefinitionRevision: Int64,
        expectedDefinition: PropertyDefinition,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              expectedDefinition.id == propertyID,
              expectedDefinition.revision == expectedDefinitionRevision,
              expectedDefinition.state == .active,
              expectedDefinition.origin == .userDefined
        else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.optionID = optionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedDefinition = expectedDefinition
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", optionID = "option_id",
           expectedDefinitionRevision = "expected_definition_revision"
    }
}

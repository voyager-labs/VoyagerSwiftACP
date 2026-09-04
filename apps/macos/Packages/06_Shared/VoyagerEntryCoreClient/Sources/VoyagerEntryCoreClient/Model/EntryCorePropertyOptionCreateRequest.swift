import Foundation

nonisolated public struct PropertyOptionCreateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    /// CreateOption 응답 대조에 쓰는 caller 측 사전 option snapshot이다
    /// (id·label·position·state). CreateOption은 기존 option을 수정하지 않고
    /// 새 option 하나만 마지막에 추가하므로, 응답의 선행 option이 이 snapshot과
    /// 정확히 일치하는지 검증하는 데 쓰이며 wire 요청에는 포함되지 않는다.
    let expectedOptions: [PropertyOption]
    let label: String
    public init(
        propertyID: PropertyID,
        expectedDefinitionRevision: Int64,
        expectedOptions: [PropertyOption],
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedOptions = expectedOptions
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
    /// RenameOption은 대상 label만 바꾼다. 응답의 나머지 option이 이 사전
    /// snapshot과 정확히 일치하는지 검증하는 데 쓰이며 wire 요청에는
    /// 포함되지 않는다.
    let expectedOptions: [PropertyOption]
    let label: String
    public init(
        propertyID: PropertyID,
        optionID: PropertyOptionID,
        expectedDefinitionRevision: Int64,
        expectedOptions: [PropertyOption],
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.optionID = optionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedOptions = expectedOptions
        self.label = label
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", optionID = "option_id",
           expectedDefinitionRevision = "expected_definition_revision",
           label
    }
}

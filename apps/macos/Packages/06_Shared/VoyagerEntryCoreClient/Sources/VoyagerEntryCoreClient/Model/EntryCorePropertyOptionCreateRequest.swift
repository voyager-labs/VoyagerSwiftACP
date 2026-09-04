import Foundation

nonisolated public struct PropertyOptionCreateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    /// CreateOption 응답 대조에 쓰는 caller 측 사전 option IDs다. 정확히 하나의
    /// 새 option이 마지막에 추가됐는지 검증하는 데 쓰이며 wire 요청에는
    /// 포함되지 않는다.
    let expectedOptionIDs: [PropertyOptionID]
    let label: String
    public init(
        propertyID: PropertyID,
        expectedDefinitionRevision: Int64,
        expectedOptionIDs: [PropertyOptionID],
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedOptionIDs = expectedOptionIDs
        self.label = label
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", expectedDefinitionRevision = "expected_definition_revision", label
    }
}

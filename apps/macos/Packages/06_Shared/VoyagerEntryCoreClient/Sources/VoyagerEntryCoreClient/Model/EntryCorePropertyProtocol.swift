import Foundation

nonisolated public struct PropertyID: Hashable, Comparable, Encodable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard PropertyWireValidation.isPropertyID(rawValue) else { throw EntryCoreClientError.protocolMismatch }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated public struct PropertyOptionID: Hashable, Encodable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard PropertyWireValidation.isPropertyID(rawValue), rawValue[rawValue.index(
            rawValue.startIndex,
            offsetBy: 14,
        )] == "7" else {
            throw EntryCoreClientError.protocolMismatch
        }
        self.rawValue = rawValue
    }
}

nonisolated public struct EntryCoreEntryID: Hashable, Encodable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard PropertyWireValidation.isEntryID(rawValue) else { throw EntryCoreClientError.protocolMismatch }
        self.rawValue = rawValue
    }
}

nonisolated public enum PropertyValueType: String, CaseIterable, Codable, Sendable {
    case text, number, date, datetime, boolean, select
}

nonisolated public enum PropertyCardinality: String, CaseIterable, Codable, Sendable { case one, many }
nonisolated public enum PropertyDefinitionState: String, Codable, Sendable { case active, disabled }
nonisolated public enum PropertyAssignmentState: String, Codable,
    Sendable { case value, null, unknown, notApplicable = "not_applicable" }
nonisolated public enum PropertyConditionNativeType: String, Codable,
    Sendable { case string, number, date, boolean, stringList = "string_list", categorical }
nonisolated public enum PropertyConditionCapabilityReason: String, Codable, Sendable {
    case definitionDisabled = "definition_disabled"
    case sourceRuntimeUnavailable = "source_runtime_unavailable"
    case unsupportedValueContract = "unsupported_value_contract"
}

nonisolated public struct PropertyConditionOperator: Hashable, Comparable, Encodable, Sendable {
    public static let canonicalValues = [
        "all",
        "any",
        "btw",
        "cn",
        "empty",
        "eq",
        "ew",
        "exists",
        "gt",
        "gte",
        "lt",
        "lte",
        "miss",
        "nbtw",
        "nc",
        "neq",
        "none",
        "rx",
        "sw",
        "today",
    ]
    public let rawValue: String

    public init(rawValue: String) throws {
        guard Self.canonicalValues.contains(rawValue) else { throw EntryCoreClientError.protocolMismatch }
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated public enum PropertyConditionCapability: Equatable, Sendable {
    case supported(
        catalogVersion: String,
        nativeType: PropertyConditionNativeType,
        allowedOperators: [PropertyConditionOperator],
    )
    case unsupported(PropertyConditionCapabilityReason)
}

nonisolated public struct PropertyOption: Equatable, Sendable {
    public let id: PropertyOptionID
    public let label: String
    public let position: Int
    public let state: PropertyDefinitionState
}

nonisolated public struct PropertyDefinition: Equatable, Sendable {
    public let id: PropertyID
    public let key: String
    public let name: String
    public let valueType: PropertyValueType
    public let cardinality: PropertyCardinality
    public let state: PropertyDefinitionState
    public let revision: Int64
    public let options: [PropertyOption]
    public let conditionCapability: PropertyConditionCapability
}

nonisolated public enum PropertyValue: Equatable, Sendable {
    case text(String), number(String), date(String), dateTime(String), boolean(Bool), select(PropertyOptionID)
    case texts([String]), numbers([String]), dates([String]), dateTimes([String]), booleans([Bool]),
         selects([PropertyOptionID])
}

nonisolated public struct PropertyTarget: Hashable, Sendable {
    public let localPath: String

    public init(localPath: String) throws {
        guard PropertyWireValidation.isLocalPath(localPath) else { throw EntryCoreClientError.protocolMismatch }
        self.localPath = localPath
    }
}

nonisolated public struct PropertyAssignment: Equatable, Sendable {
    public let propertyID: PropertyID
    public let entryID: EntryCoreEntryID
    public let valueType: PropertyValueType
    public let cardinality: PropertyCardinality
    public let state: PropertyAssignmentState
    public let revision: Int64
    public let value: PropertyValue?
}

nonisolated public enum PropertyDesiredState: Equatable, Sendable {
    case null, unknown, notApplicable
    case value(PropertyValueType, PropertyCardinality, PropertyValue)
}

nonisolated public struct PropertyChangeTarget: Equatable, Sendable {
    public let target: PropertyTarget
    /// The canonical entry resolved during discovery/prepare. It is optional for
    /// prepare requests and required by the execute operation.
    public let entryID: EntryCoreEntryID?
    public let propertyID: PropertyID
    public let expectedDefinitionRevision: Int64
    public let expectedAssignmentRevision: Int64
    public let desired: PropertyDesiredState

    public init(
        target: PropertyTarget,
        propertyID: PropertyID,
        expectedDefinitionRevision: Int64,
        expectedAssignmentRevision: Int64,
        desired: PropertyDesiredState,
        entryID: EntryCoreEntryID? = nil,
    ) throws {
        guard expectedDefinitionRevision >= 1, expectedAssignmentRevision >= 0,
              PropertyWireValidation.desired(desired) else { throw EntryCoreClientError.protocolMismatch }
        self.target = target
        self.entryID = entryID
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.expectedAssignmentRevision = expectedAssignmentRevision
        self.desired = desired
    }
}

nonisolated public struct PropertyPreparedChange: Equatable, Sendable {
    public let target: PropertyTarget
    public let propertyID: PropertyID
    public let entryID: EntryCoreEntryID
    public let before: PropertyAssignment?
    public let after: PropertyDesiredState
}

nonisolated public struct PropertyDefinitionPage: Equatable, Sendable {
    public let definitions: [PropertyDefinition]
    public let nextPageToken: String?
    public let hasMore: Bool
}

nonisolated public struct PropertyAssignmentPage: Equatable, Sendable {
    public let assignments: [PropertyAssignment]
    public let nextPageToken: String?
    public let hasMore: Bool
}

nonisolated public struct PropertyChangeProposal: Equatable, Sendable {
    public let changes: [PropertyPreparedChange]
    public let requiresConfirmation: Bool
}

nonisolated public struct PropertyDefinitionListRequest: Encodable, Sendable {
    let pageSize: Int
    let requestedPropertyIDs: [PropertyID]
    let includeDisabled: Bool?
    let pageToken: String?
    public init(
        pageSize: Int,
        requestedPropertyIDs: [PropertyID] = [],
        includeDisabled: Bool? = nil,
        pageToken: String? = nil,
    ) throws {
        try PropertyWireValidation.page(pageSize, ids: requestedPropertyIDs, token: pageToken)
        self.pageSize = pageSize
        self.requestedPropertyIDs = requestedPropertyIDs
        self.includeDisabled = includeDisabled
        self.pageToken = pageToken
    }

    enum CodingKeys: String,
        CodingKey
    { case pageSize = "page_size", requestedPropertyIDs = "requested_property_ids",
           includeDisabled = "include_disabled",
           pageToken = "page_token"
    }
}

nonisolated public struct PropertyDefinitionCreateRequest: Encodable, Sendable {
    struct Option: Encodable { let label: String }
    let key: String
    let name: String
    let valueType: PropertyValueType
    let cardinality: PropertyCardinality
    let options: [Option]?
    public init(
        key: String,
        name: String,
        valueType: PropertyValueType,
        cardinality: PropertyCardinality,
        optionLabels: [String]? = nil,
    ) throws {
        guard PropertyWireValidation.short(key), PropertyWireValidation.short(name), (optionLabels?.count ?? 0) <= 256,
              optionLabels?.allSatisfy(PropertyWireValidation.short) ?? true,
              optionLabels == nil || valueType == .select else { throw EntryCoreClientError.protocolMismatch }
        self.key = key
        self.name = name
        self.valueType = valueType
        self.cardinality = cardinality
        options = optionLabels?.map(Option.init)
    }

    enum CodingKeys: String, CodingKey { case key, name, valueType = "value_type", cardinality, options }
}

nonisolated public struct PropertyDefinitionUpdateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    let name: String
    public init(propertyID: PropertyID, expectedDefinitionRevision: Int64, name: String) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(name) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.name = name
    }

    enum CodingKeys: String,
        CodingKey { case propertyID = "property_id", expectedDefinitionRevision = "expected_definition_revision", name }
}

nonisolated public struct PropertyDefinitionDisableRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    public init(propertyID: PropertyID, expectedDefinitionRevision: Int64) throws {
        guard expectedDefinitionRevision >= 1 else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
    }

    enum CodingKeys: String,
        CodingKey { case propertyID = "property_id", expectedDefinitionRevision = "expected_definition_revision" }
}

nonisolated public struct PropertyOptionCreateRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    let label: String
    public init(propertyID: PropertyID, expectedDefinitionRevision: Int64, label: String) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
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
    let label: String
    public init(
        propertyID: PropertyID,
        optionID: PropertyOptionID,
        expectedDefinitionRevision: Int64,
        label: String,
    ) throws {
        guard expectedDefinitionRevision >= 1,
              PropertyWireValidation.short(label) else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.optionID = optionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.label = label
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", optionID = "option_id",
           expectedDefinitionRevision = "expected_definition_revision",
           label
    }
}

nonisolated public struct PropertyOptionReorderRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let expectedDefinitionRevision: Int64
    let optionIDs: [PropertyOptionID]
    public init(propertyID: PropertyID, expectedDefinitionRevision: Int64, optionIDs: [PropertyOptionID]) throws {
        guard expectedDefinitionRevision >= 1, (1 ... 256).contains(optionIDs.count),
              Set(optionIDs).count == optionIDs.count else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.expectedDefinitionRevision = expectedDefinitionRevision
        self.optionIDs = optionIDs
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", expectedDefinitionRevision = "expected_definition_revision",
           optionIDs = "option_ids"
    }
}

nonisolated public struct PropertyOptionDisableRequest: Encodable, Sendable {
    let propertyID: PropertyID
    let optionID: PropertyOptionID
    let expectedDefinitionRevision: Int64
    public init(propertyID: PropertyID, optionID: PropertyOptionID, expectedDefinitionRevision: Int64) throws {
        guard expectedDefinitionRevision >= 1 else { throw EntryCoreClientError.protocolMismatch }
        self.propertyID = propertyID
        self.optionID = optionID
        self.expectedDefinitionRevision = expectedDefinitionRevision
    }

    enum CodingKeys: String,
        CodingKey
    { case propertyID = "property_id", optionID = "option_id",
           expectedDefinitionRevision = "expected_definition_revision"
    }
}

nonisolated public struct PropertyAssignmentListRequest: Encodable, Sendable {
    let pageSize: Int
    let requestedPropertyIDs: [PropertyID]
    let target: PropertyTarget
    let pageToken: String?
    public init(
        pageSize: Int,
        target: PropertyTarget,
        pageToken: String? = nil,
        requestedPropertyIDs: [PropertyID] = [],
    ) throws {
        try PropertyWireValidation.page(pageSize, ids: requestedPropertyIDs, token: pageToken)
        self.pageSize = pageSize
        self.requestedPropertyIDs = requestedPropertyIDs
        self.target = target
        self.pageToken = pageToken
    }

    public init(
        pageSize: Int,
        requestedPropertyIDs: [PropertyID],
        target: PropertyTarget,
        pageToken: String? = nil,
    ) throws {
        try self.init(
            pageSize: pageSize,
            target: target,
            pageToken: pageToken,
            requestedPropertyIDs: requestedPropertyIDs,
        )
    }

    enum CodingKeys: String,
        CodingKey
    { case pageSize = "page_size", requestedPropertyIDs = "requested_property_ids", target,
           pageToken = "page_token"
    }
}

nonisolated public struct PropertyChangeRequest: Encodable, Sendable {
    let changes: [PropertyChangeTarget]
    public init(changes: [PropertyChangeTarget]) throws {
        guard (1 ... 256).contains(changes.count) else { throw EntryCoreClientError.protocolMismatch }
        self.changes = changes
    }
}

nonisolated public enum PropertyConditionCombinator: String, Codable, Sendable { case all, any }

nonisolated public enum PropertyConditionOperand: Equatable, Sendable {
    case none
    case text([String]), number([String]), date([String]), select([PropertyOptionID]), boolean(Bool)
}

nonisolated public struct PropertyCondition: Equatable, Sendable {
    public let propertyID: PropertyID
    public let `operator`: PropertyConditionOperator
    public let operand: PropertyConditionOperand
    public init(propertyID: PropertyID, operator: PropertyConditionOperator, operand: PropertyConditionOperand) {
        self.propertyID = propertyID
        self.operator = `operator`
        self.operand = operand
    }
}

nonisolated public struct PropertyConditionQueryRequest: Encodable, Sendable {
    let targets: [PropertyTarget]
    let combinator: PropertyConditionCombinator
    let conditions: [PropertyCondition]
    let projectionPropertyIDs: [PropertyID]
    let evaluationDate: String
    let pageSize: Int
    let pageToken: String?
    public init(
        targets: [PropertyTarget],
        combinator: PropertyConditionCombinator,
        conditions: [PropertyCondition],
        evaluationDate: String,
        pageSize: Int,
        pageToken: String? = nil,
        projectionPropertyIDs: [PropertyID] = [],
    ) throws {
        let ids = conditions.map(\.propertyID)
        let unique = Set(ids + projectionPropertyIDs).count
        guard (1 ... 256).contains(targets.count), Set(targets).count == targets.count,
              (1 ... 256).contains(conditions.count), Set(ids).count == ids.count,
              conditions.allSatisfy(PropertyWireValidation.condition),
              projectionPropertyIDs.count <= 256, projectionPropertyIDs == projectionPropertyIDs.sorted(),
              Set(projectionPropertyIDs).count == projectionPropertyIDs.count,
              targets.count * unique <= 4096,
              PropertyWireValidation.date(evaluationDate) else { throw EntryCoreClientError.protocolMismatch }
        try PropertyWireValidation.page(pageSize, ids: projectionPropertyIDs, token: pageToken)
        self.targets = targets
        self.combinator = combinator
        self.conditions = conditions
        self.projectionPropertyIDs = projectionPropertyIDs
        self.evaluationDate = evaluationDate
        self.pageSize = pageSize
        self.pageToken = pageToken
    }

    enum CodingKeys: String,
        CodingKey
    { case targets, combinator, conditions, projectionPropertyIDs = "projection_property_ids",
           evaluationDate = "evaluation_date", pageSize = "page_size", pageToken = "page_token"
    }
}

nonisolated public struct PropertyConditionQueryItem: Equatable, Sendable {
    public let candidateIndex: Int
    public let entryID: EntryCoreEntryID
    public let projection: [PropertyAssignment]
}

nonisolated public struct PropertyConditionQueryPage: Equatable, Sendable {
    public let items: [PropertyConditionQueryItem]
    public let unresolvedCandidateIndices: [Int]
    public let catalogVersion: String
    public let nextPageToken: String?
    public let hasMore: Bool
}

public extension PropertyID { func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
} }
public extension PropertyOptionID { func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
} }
public extension EntryCoreEntryID { func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
} }
public extension PropertyConditionOperator {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PropertyTarget: Encodable {
    enum CodingKeys: String, CodingKey { case kind, localPath = "local_path" }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("local_path", forKey: .kind)
        try container.encode(localPath, forKey: .localPath)
    }
}

extension PropertyValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value), let .number(value), let .date(value), let .dateTime(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .select(value): try container.encode(value)
        case let .texts(value), let .numbers(value), let .dates(value),
             let .dateTimes(value): try container.encode(value)
        case let .booleans(value): try container.encode(value)
        case let .selects(value): try container.encode(value)
        }
    }
}

extension PropertyDesiredState: Encodable {
    enum CodingKeys: String, CodingKey { case state, valueType = "value_type", cardinality, value }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null: try container.encode("null", forKey: .state)
        case .unknown: try container.encode("unknown", forKey: .state)
        case .notApplicable: try container.encode("not_applicable", forKey: .state)
        case let .value(type, cardinality, value): try container.encode("value", forKey: .state)
            try container.encode(type, forKey: .valueType)
            try container.encode(cardinality, forKey: .cardinality)
            try container.encode(value, forKey: .value)
        }
    }
}

extension PropertyChangeTarget: Encodable {
    enum CodingKeys: String,
        CodingKey
    { case target, entryID = "entry_id", propertyID = "property_id",
           expectedDefinitionRevision = "expected_definition_revision",
           expectedAssignmentRevision = "expected_assignment_revision", desired
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(entryID, forKey: .entryID)
        try container.encode(propertyID, forKey: .propertyID)
        try container.encode(expectedDefinitionRevision, forKey: .expectedDefinitionRevision)
        try container.encode(expectedAssignmentRevision, forKey: .expectedAssignmentRevision)
        try container.encode(desired, forKey: .desired)
    }
}

extension PropertyCondition: Encodable {
    enum CodingKeys: String, CodingKey { case propertyID = "property_id", `operator`, operand }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(propertyID, forKey: .propertyID)
        try container.encode(`operator`, forKey: .operator)
        try container.encode(operand, forKey: .operand)
    }
}

extension PropertyConditionOperand: Encodable {
    enum CodingKeys: String, CodingKey { case kind, values, boolean }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try container.encode("none", forKey: .kind)
        case let .text(value): try container.encode("text", forKey: .kind)
            try container.encode(value, forKey: .values)
        case let .number(value): try container.encode("number", forKey: .kind)
            try container.encode(value, forKey: .values)
        case let .date(value): try container.encode("date", forKey: .kind)
            try container.encode(value, forKey: .values)
        case let .select(value): try container.encode("option_ref", forKey: .kind)
            try container.encode(value, forKey: .values)
        case let .boolean(value): try container.encode("boolean", forKey: .kind)
            try container.encode(value, forKey: .boolean)
        }
    }
}

enum PropertyWireValidation {
    static func isPropertyID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36, bytes[8] == 45, bytes[13] == 45, bytes[18] == 45, bytes[23] == 45 else { return false }
        for (index, byte) in bytes.enumerated()
            where ![8, 13, 18, 23]
            .contains(index)
        {
            guard (48 ... 57).contains(byte) || (97 ... 102).contains(byte) else { return false }
        }
        return ["8", "9", "a", "b"].contains(String(value[value.index(value.startIndex, offsetBy: 19)]))
    }

    static func isEntryID(_ value: String) -> Bool {
        guard value.hasPrefix("ent:"), value.utf8.count == 47 else { return false }
        var encoded = String(value.dropFirst(4)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
            of: "_",
            with: "/",
        )
        encoded += "="
        guard let decoded = Data(base64Encoded: encoded), decoded.count == 32 else { return false }
        let canonical = decoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return canonical == String(value.dropFirst(4))
    }

    static func short(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
    }

    static func token(_ value: String?) -> Bool {
        value
            .map { (1 ... 4096).contains($0.utf8.count) && $0.unicodeScalars.allSatisfy(\.isASCII) } ?? true
    }

    static func date(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: value) else { return false }
        return formatter.string(from: parsed) == value
    }

    static func timestamp(_ value: String) -> Bool {
        guard value.utf8.count <= 64,
              value.range(
                  of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$"#,
                  options: .regularExpression,
              ) != nil else { return false }
        let base: String
        if let separator = value.firstIndex(of: ".") {
            base = String(value[..<separator]) + "Z"
            let fraction = value[value.index(after: separator) ..< value.index(before: value.endIndex)]
            guard !fraction.hasSuffix("0") else { return false }
        } else {
            base = value
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        guard let parsed = formatter.date(from: base) else { return false }
        return formatter.string(from: parsed) == base
    }

    static func isLocalPath(_ value: String) -> Bool {
        (2 ... 4096).contains(value.utf8.count) && value
            .hasPrefix("/") && !value.hasSuffix("/") && !value.contains("//") && value.split(separator: "/")
            .allSatisfy { $0 != "." && $0 != ".." } && value.unicodeScalars
            .allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
    }

    static func page(_ size: Int, ids: [PropertyID], token: String?) throws {
        guard (1 ... 256).contains(size),
              ids.count <= 256,
              ids == ids.sorted(),
              Set(ids).count == ids.count,
              self.token(token)
        else {
            throw EntryCoreClientError
                .protocolMismatch
        }
    }

    static func desired(_ desired: PropertyDesiredState)
        -> Bool
    {
        if case let .value(type, cardinality, value) = desired
        { return matches(
            value,
            type: type,
            cardinality: cardinality,
        ) }
        return true
    }

    static func condition(_ condition: PropertyCondition) -> Bool {
        switch condition.operator.rawValue {
        case "empty", "exists", "today": condition.operand == .none
        case "btw", "nbtw": rangeOperand(condition.operand)
        case "all", "any", "miss", "none": collectionOperand(condition.operand)
        case "cn", "nc", "sw", "ew", "rx": textOperand(condition.operand)
        case "eq": equalityOperand(condition.operand)
        case "neq", "gt", "gte", "lt", "lte": scalarOperand(condition.operand)
        default: false
        }
    }

    static func rangeOperand(_ operand: PropertyConditionOperand) -> Bool {
        switch operand {
        case let .number(values): values.count == 2 && values.allSatisfy(decimal)
        case let .date(values): values.count == 2 && values.allSatisfy(date)
        default: false
        }
    }

    static func collectionOperand(_ operand: PropertyConditionOperand) -> Bool {
        switch operand {
        case let .text(values): !values.isEmpty && values.count <= 256 && values.allSatisfy { $0.utf8.count <= 4096 }
        case let .select(values): !values.isEmpty && values.count <= 256
        default: false
        }
    }

    static func textOperand(_ operand: PropertyConditionOperand) -> Bool {
        guard case let .text(values) = operand else { return false }
        return values.count == 1 && values[0].utf8.count <= 4096
    }

    static func equalityOperand(_ operand: PropertyConditionOperand) -> Bool {
        if case .boolean = operand { return true }
        return scalarOperand(operand)
    }

    static func scalarOperand(_ operand: PropertyConditionOperand) -> Bool {
        switch operand {
        case let .text(values): values.count == 1 && values[0].utf8.count <= 4096
        case let .number(values): values.count == 1 && values.allSatisfy(decimal)
        case let .date(values): values.count == 1 && values.allSatisfy(date)
        default: false
        }
    }

    static func decimal(_ value: String) -> Bool {
        guard value.utf8.count <= 64,
              value.range(of: #"^-?(0|[1-9]\d*)(\.\d*[1-9])?$"#, options: .regularExpression) != nil,
              value != "-0"
        else { return false }
        let unsigned = value.hasPrefix("-") ? String(value.dropFirst()) : value
        let components = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        let fractionalCount = components.count == 2 ? components[1].count : 0
        return fractionalCount <= 18 && components[0].count + fractionalCount <= 38
    }

    static func matches(
        _ value: PropertyValue,
        type: PropertyValueType,
        cardinality: PropertyCardinality,
    ) -> Bool {
        switch cardinality {
        case .one: matchesScalar(value, type: type)
        case .many: matchesMany(value, type: type)
        }
    }

    static func matchesScalar(_ value: PropertyValue, type: PropertyValueType) -> Bool {
        switch (value, type) {
        case let (.text(raw), .text): raw.utf8.count <= 4096
        case let (.number(raw), .number): decimal(raw)
        case let (.date(raw), .date): date(raw)
        case let (.dateTime(raw), .datetime): timestamp(raw)
        case (.boolean, .boolean), (.select, .select): true
        default: false
        }
    }

    static func matchesMany(_ value: PropertyValue, type: PropertyValueType) -> Bool {
        switch (value, type) {
        case let (.texts(values), .text):
            values.count <= 256 && values.allSatisfy { $0.utf8.count <= 4096 }
        case let (.numbers(values), .number):
            values.count <= 256 && values.allSatisfy(decimal)
        case let (.dates(values), .date):
            values.count <= 256 && values.allSatisfy(date)
        case let (.dateTimes(values), .datetime):
            values.count <= 256 && values.allSatisfy(timestamp)
        case let (.booleans(values), .boolean): values.count <= 256
        case let (.selects(values), .select): values.count <= 256
        default: false
        }
    }
}

import Foundation

enum EntryCorePropertyDecodedResponse: Equatable {
    case definitionPage(PropertyDefinitionPage)
    case definition(PropertyDefinition)
    case assignmentPage(PropertyAssignmentPage)
    case proposal(PropertyChangeProposal)
    case assignments([PropertyAssignment])
    case queryPage(PropertyConditionQueryPage)
}

enum EntryCorePropertyResponseDecoder {
    static func decode(
        _ raw: [UInt8],
        method: EntryCoreMethod,
        expectedRequestID: String,
    ) throws -> EntryCorePropertyDecodedResponse {
        let root: StrictJSONValue
        do { root = try StrictJSONParser.parse(raw) } catch { throw EntryCoreClientError.malformedResponse }
        guard case .object = root, case let .string(id)? = root.field(named: "request_id"),
              case let .bool(ok)? = root.field(named: "ok"), id.utf8.count <= 128
        else {
            throw EntryCoreClientError.protocolMismatch
        }
        let fields = ok ? root.objectFields(exactly: ["request_id", "ok", "result"]) : root.objectFields(exactly: [
            "request_id",
            "ok",
            "error",
        ])
        guard let fields else { throw EntryCoreClientError.protocolMismatch }
        guard !expectedRequestID.isEmpty,
              id.utf8.elementsEqual(expectedRequestID.utf8) else { throw EntryCoreClientError.requestIDMismatch }
        if !ok { try decodeError(fields["error"]) }
        guard let result = fields["result"] else { throw EntryCoreClientError.protocolMismatch }
        return try decodeSuccess(result, method: method)
    }
}

private extension EntryCorePropertyResponseDecoder {
    static let definitionMethods: Set<EntryCoreMethod> = [
        .propertyDefinitionCreate,
        .propertyDefinitionUpdate,
        .propertyDefinitionDisable,
        .propertyOptionCreate,
        .propertyOptionUpdate,
        .propertyOptionReorder,
        .propertyOptionDisable,
    ]

    static func decodeSuccess(
        _ result: StrictJSONValue,
        method: EntryCoreMethod,
    ) throws -> EntryCorePropertyDecodedResponse {
        if method == .propertyDefinitionList { return try .definitionPage(definitionPage(result)) }
        if definitionMethods.contains(method) {
            guard let value = result.objectFields(exactly: ["definition"])?["definition"] else { throw mismatch }
            return try .definition(definition(value))
        }
        if method == .propertyAssignmentList { return try .assignmentPage(assignmentPage(result)) }
        if method == .propertyChangePrepare { return try .proposal(proposal(result)) }
        if method == .propertyChangeExecute {
            guard let value = result.objectFields(exactly: ["assignments"])?["assignments"] else { throw mismatch }
            return try .assignments(assignments(value, requireNonempty: true))
        }
        if method == .propertyConditionQuery { return try .queryPage(queryPage(result)) }
        throw mismatch
    }

    static var mismatch: EntryCoreClientError {
        .protocolMismatch
    }

    static func decodeError(_ value: StrictJSONValue?) throws -> Never {
        guard let fields = value?.objectFields(exactly: ["code", "message"]), case let .string(raw)? = fields["code"],
              case let .string(message)? = fields["message"], let code = EntryCoreServerErrorCode(rawValue: raw),
              message == code.canonicalMessage else { throw mismatch }
        throw EntryCoreClientError.server(code)
    }

    static func definitionPage(_ value: StrictJSONValue) throws -> PropertyDefinitionPage {
        guard let fields = value.objectFields(exactly: fields(
            value,
            required: ["definitions", "has_more"],
            optional: ["next_page_token"],
        )),
            case let .array(values)? = fields["definitions"], values.count <= 256,
            case let .bool(hasMore)? = fields["has_more"] else { throw mismatch }
        let definitions = try values.map(definition)
        guard Set(definitions.map(\.id)).count == definitions.count else { throw mismatch }
        let token = try pageToken(fields["next_page_token"])
        guard hasMore == (token != nil) else { throw mismatch }
        return PropertyDefinitionPage(definitions: definitions, nextPageToken: token, hasMore: hasMore)
    }

    static func definition(_ value: StrictJSONValue) throws -> PropertyDefinition {
        guard let fields = value.objectFields(exactly: [
            "property_id",
            "key",
            "name",
            "value_type",
            "cardinality",
            "state",
            "origin",
            "revision",
            "options",
            "condition_capability",
        ]),
            case let .string(id)? = fields["property_id"], case let .string(key)? = fields["key"],
            case let .string(name)? = fields["name"],
            case let .string(typeRaw)? = fields["value_type"],
            case let .string(cardinalityRaw)? = fields["cardinality"],
            case let .string(stateRaw)? = fields["state"],
            case let .string(originRaw)? = fields["origin"], let revision = integer(fields["revision"]), revision >= 1,
            case let .array(optionValues)? = fields["options"], optionValues.count <= 256,
            let type = PropertyValueType(rawValue: typeRaw),
            let cardinality = PropertyCardinality(rawValue: cardinalityRaw),
            let state = PropertyDefinitionState(rawValue: stateRaw),
            let origin = PropertyDefinitionOrigin(rawValue: originRaw), PropertyWireValidation.short(key),
            PropertyWireValidation.short(name) else { throw mismatch }
        let options = try optionValues.map(option)
        guard type == .select || options.isEmpty, Set(options.map(\.id)).count == options.count,
              zip(options, options.dropFirst()).allSatisfy({ $0.position < $1.position }) else { throw mismatch }
        let conditionCapability = try capability(fields["condition_capability"])
        try validate(
            conditionCapability,
            matchesValueType: type,
            cardinality: cardinality,
            state: state,
            origin: origin,
        )
        return try PropertyDefinition(
            id: PropertyID(rawValue: id),
            key: key,
            name: name,
            valueType: type,
            cardinality: cardinality,
            state: state,
            origin: origin,
            revision: revision,
            options: options,
            conditionCapability: conditionCapability,
        )
    }

    /// capability가 definition origin·lifecycle과 value contract에서 유도되는
    /// native type 및 Registry relation의 전체 operator 집합과 정확히 일치하는지
    /// 검증한다 (Go protocol/schema/property_capability_validation.go와 같은 경계).
    /// evaluator가 항상 false로 평가하는 operator를 광고하거나 origin·lifecycle과
    /// 모순되는 지원 상태를 반환하면 client가 잘못된 operand UI·기능 상태를 구성할
    /// 수 있으므로 fail-closed로 거절한다.
    static func validate(
        _ capability: PropertyConditionCapability,
        matchesValueType valueType: PropertyValueType,
        cardinality: PropertyCardinality,
        state: PropertyDefinitionState,
        origin: PropertyDefinitionOrigin,
    ) throws {
        switch capability {
        case let .supported(_, nativeType, allowedOperators):
            guard origin == .userDefined,
                  state == .active,
                  let expectedNativeType = PropertyConditionRelation.nativeType(
                      for: valueType,
                      cardinality: cardinality,
                  ),
                  nativeType == expectedNativeType,
                  allowedOperators == PropertyConditionRelation.operators(for: expectedNativeType)
            else { throw mismatch }
        case let .unsupported(reason):
            switch (state, reason) {
            case (.disabled, .definitionDisabled):
                break
            case (.active, .sourceRuntimeUnavailable):
                // ConditionCapabilityFor는 built-in 정의에만 이 사유를 발행한다.
                guard origin == .builtIn else { throw mismatch }
            case (.active, .unsupportedValueContract):
                guard origin == .userDefined,
                      PropertyConditionRelation.nativeType(for: valueType, cardinality: cardinality) == nil
                else { throw mismatch }
            default:
                throw mismatch
            }
        }
    }

    static func option(_ value: StrictJSONValue) throws -> PropertyOption {
        guard let fields = value.objectFields(exactly: ["option_id", "label", "position", "state"]),
              case let .string(id)? = fields["option_id"], case let .string(label)? = fields["label"],
              let position = integer(fields["position"]), position >= 1, case let .string(stateRaw)? = fields["state"],
              let state = PropertyDefinitionState(rawValue: stateRaw),
              PropertyWireValidation.short(label) else { throw mismatch }
        return try PropertyOption(
            id: PropertyOptionID(rawValue: id),
            label: label,
            position: Int(position),
            state: state,
        )
    }

    static func capability(_ value: StrictJSONValue?) throws -> PropertyConditionCapability {
        guard let value, case .object = value,
              case let .bool(supported)? = value.field(named: "supported") else { throw mismatch }
        if supported {
            guard let fields = value.objectFields(exactly: [
                "supported",
                "evaluation_scope",
                "catalog_version",
                "native_type",
                "allowed_operators",
            ]),
                fields["evaluation_scope"] == .string("local_assignment"),
                // relation table은 고정 catalog 버전을 미러링하므로 다른 버전의
                // semantics는 승인하지 않는다.
                fields["catalog_version"] == .string(PropertyConditionCatalog.version),
                case let .string(nativeRaw)? = fields["native_type"],
                let native = PropertyConditionNativeType(rawValue: nativeRaw),
                case let .array(rawOperators)? = fields["allowed_operators"] else { throw mismatch }
            let operators = try rawOperators
                .map { value -> PropertyConditionOperator in guard case let .string(raw) = value else { throw mismatch }
                    return try PropertyConditionOperator(rawValue: raw)
                }
            guard operators == operators.sorted(), Set(operators).count == operators.count else { throw mismatch }
            return .supported(
                catalogVersion: PropertyConditionCatalog.version,
                nativeType: native,
                allowedOperators: operators,
            )
        }
        guard let fields = value.objectFields(exactly: ["supported", "reason"]),
              case let .string(raw)? = fields["reason"],
              let reason = PropertyConditionCapabilityReason(rawValue: raw) else { throw mismatch }
        return .unsupported(reason)
    }

    static func assignmentPage(_ value: StrictJSONValue) throws -> PropertyAssignmentPage {
        guard let fields = value.objectFields(exactly: fields(
            value,
            required: ["assignments", "has_more"],
            optional: ["next_page_token"],
        )),
            case let .bool(hasMore)? = fields["has_more"], let raw = fields["assignments"] else { throw mismatch }
        let values = try assignments(raw, requireNonempty: false)
        guard values.count <= 256, Set(values.map(\.propertyID)).count == values.count else { throw mismatch }
        let token = try pageToken(fields["next_page_token"])
        guard hasMore == (token != nil) else { throw mismatch }
        return PropertyAssignmentPage(assignments: values, nextPageToken: token, hasMore: hasMore)
    }

    static func assignments(_ value: StrictJSONValue, requireNonempty: Bool) throws -> [PropertyAssignment] {
        guard case let .array(values) = value, values.count <= 256,
              !requireNonempty || !values.isEmpty else { throw mismatch }
        return try values.map(assignment)
    }

    static func assignment(_ value: StrictJSONValue) throws -> PropertyAssignment {
        guard let fields = value.objectFields(exactly: fields(
            value,
            required: ["property_id", "entry_id", "value_type", "cardinality", "state", "revision"],
            optional: ["value"],
        )),
            case let .string(pid)? = fields["property_id"], case let .string(eid)? = fields["entry_id"],
            case let .string(typeRaw)? = fields["value_type"], let type = PropertyValueType(rawValue: typeRaw),
            case let .string(cardinalityRaw)? = fields["cardinality"],
            let cardinality = PropertyCardinality(rawValue: cardinalityRaw),
            case let .string(stateRaw)? = fields["state"], let state = PropertyAssignmentState(rawValue: stateRaw),
            let revision = integer(fields["revision"]), revision >= 1 else { throw mismatch }
        let payload = try fields["value"].map { try propertyValue($0, type: type, cardinality: cardinality) }
        guard (state == .value) == (payload != nil) else { throw mismatch }
        return try PropertyAssignment(
            propertyID: PropertyID(rawValue: pid),
            entryID: EntryCoreEntryID(rawValue: eid),
            valueType: type,
            cardinality: cardinality,
            state: state,
            revision: revision,
            value: payload,
        )
    }

    static func propertyValue(
        _ value: StrictJSONValue,
        type: PropertyValueType,
        cardinality: PropertyCardinality,
    ) throws -> PropertyValue {
        if cardinality == .many { return try manyValue(value, type: type) }
        return try scalarValue(value, type: type)
    }

    static func manyValue(_ value: StrictJSONValue, type: PropertyValueType) throws -> PropertyValue {
        guard case let .array(items) = value, items.count <= 256 else { throw mismatch }
        switch type {
        case .boolean: return try .booleans(items.map(bool))
        case .select: return try .selects(items.map { try PropertyOptionID(rawValue: string($0)) })
        case .text: return try manyTextValue(items)
        case .number: let values = try items.map(string)
            guard values.allSatisfy(decimal) else { throw mismatch }
            return .numbers(values)
        case .date: let values = try items.map(string)
            guard values.allSatisfy(PropertyWireValidation.date) else { throw mismatch }
            return .dates(values)
        case .datetime: let values = try items.map(string)
            guard values.allSatisfy(timestamp) else { throw mismatch }
            return .dateTimes(values)
        }
    }

    static func manyTextValue(_ items: [StrictJSONValue]) throws -> PropertyValue {
        let values = try items.map(string)
        guard values.allSatisfy({ $0.utf8.count <= 4096 }) else { throw mismatch }
        return .texts(values)
    }

    static func scalarValue(_ value: StrictJSONValue, type: PropertyValueType) throws -> PropertyValue {
        switch type {
        case .boolean: return try .boolean(bool(value))
        case .select: return try .select(PropertyOptionID(rawValue: string(value)))
        case .text: let raw = try string(value)
            guard raw.utf8.count <= 4096 else { throw mismatch }
            return .text(raw)
        case .number: let raw = try string(value)
            guard decimal(raw) else { throw mismatch }
            return .number(raw)
        case .date: let raw = try string(value)
            guard PropertyWireValidation.date(raw) else { throw mismatch }
            return .date(raw)
        case .datetime: let raw = try string(value)
            guard timestamp(raw) else { throw mismatch }
            return .dateTime(raw)
        }
    }

    static func proposal(_ value: StrictJSONValue) throws -> PropertyChangeProposal {
        guard let fields = value.objectFields(exactly: ["changes", "requires_confirmation"]),
              case let .array(values)? = fields["changes"],
              (1 ... 256).contains(values.count), fields["requires_confirmation"] == .bool(true) else { throw mismatch }
        return try PropertyChangeProposal(changes: values.map(prepared), requiresConfirmation: true)
    }

    static func prepared(_ value: StrictJSONValue) throws -> PropertyPreparedChange {
        guard let fields = value.objectFields(exactly: ["target", "property_id", "entry_id", "before", "after"]),
              case let .string(pid)? = fields["property_id"], case let .string(eid)? = fields["entry_id"],
              let targetValue = fields["target"],
              let afterValue = fields["after"], let beforeValue = fields["before"] else { throw mismatch }
        let propertyID = try PropertyID(rawValue: pid)
        let entryID = try EntryCoreEntryID(rawValue: eid)
        let before: PropertyAssignment? = beforeValue == .null ? nil : try assignment(beforeValue)
        if let before, before.propertyID != propertyID || before.entryID != entryID {
            throw mismatch
        }
        return try PropertyPreparedChange(
            target: target(targetValue),
            propertyID: propertyID,
            entryID: entryID,
            before: before,
            after: desired(afterValue),
        )
    }

    static func desired(_ value: StrictJSONValue) throws -> PropertyDesiredState {
        if let fields = value.objectFields(exactly: ["state"]), case let .string(state)? = fields["state"] {
            switch state {
            case "null": return .null
            case "unknown": return .unknown
            case "not_applicable": return .notApplicable
            default: throw mismatch
            }
        }
        guard let fields = value.objectFields(exactly: ["state", "value_type", "cardinality", "value"]),
              fields["state"] == .string("value"),
              case let .string(typeRaw)? = fields["value_type"], let type = PropertyValueType(rawValue: typeRaw),
              case let .string(cardinalityRaw)? = fields["cardinality"],
              let cardinality = PropertyCardinality(rawValue: cardinalityRaw),
              let raw = fields["value"] else { throw mismatch }
        return try .value(type, cardinality, propertyValue(raw, type: type, cardinality: cardinality))
    }

    static func target(_ value: StrictJSONValue) throws -> PropertyTarget {
        guard let fields = value.objectFields(exactly: ["kind", "local_path"]), fields["kind"] == .string("local_path"),
              case let .string(path)? = fields["local_path"] else { throw mismatch }
        return try PropertyTarget(localPath: path)
    }

    static func queryPage(_ value: StrictJSONValue) throws -> PropertyConditionQueryPage {
        guard let fields = value.objectFields(exactly: fields(
            value,
            required: ["items", "unresolved_candidate_indices", "catalog_version", "has_more"],
            optional: ["next_page_token"],
        )),
            case let .array(rawItems)? = fields["items"],
            case let .array(rawUnresolved)? = fields["unresolved_candidate_indices"],
            fields["catalog_version"] == .string(PropertyConditionCatalog.version),
            case let .bool(hasMore)? = fields["has_more"] else { throw mismatch }
        let items = try rawItems.map(queryItem)
        let unresolved = try rawUnresolved.map { guard let value = integer($0), value >= 0 else { throw mismatch }
            return Int(value)
        }
        guard zip(items, items.dropFirst()).allSatisfy({ $0.candidateIndex < $1.candidateIndex }),
              unresolved == unresolved.sorted(), Set(unresolved).count == unresolved.count else { throw mismatch }
        let token = try pageToken(fields["next_page_token"])
        guard hasMore == (token != nil) else { throw mismatch }
        return PropertyConditionQueryPage(
            items: items,
            unresolvedCandidateIndices: unresolved,
            catalogVersion: PropertyConditionCatalog.version,
            nextPageToken: token,
            hasMore: hasMore,
        )
    }

    static func queryItem(_ value: StrictJSONValue) throws -> PropertyConditionQueryItem {
        guard let fields = value.objectFields(exactly: ["candidate_index", "entry_id", "projection"]),
              let index = integer(fields["candidate_index"]), index >= 0,
              case let .string(eid)? = fields["entry_id"],
              let projectionValue = fields["projection"] else { throw mismatch }
        let projection = try assignments(projectionValue, requireNonempty: false)
        let entryID = try EntryCoreEntryID(rawValue: eid)
        guard projection.map(\.propertyID) == projection.map(\.propertyID).sorted(),
              Set(projection.map(\.propertyID)).count == projection.count,
              projection.allSatisfy({ $0.entryID == entryID }) else { throw mismatch }
        return PropertyConditionQueryItem(candidateIndex: Int(index), entryID: entryID, projection: projection)
    }

    static func fields(_ value: StrictJSONValue, required: Set<String>, optional: Set<String>) -> Set<String> {
        guard case let .object(members) = value else { return [] }
        let names = Set(members.map(\.name))
        return required.isSubset(of: names) && names.isSubset(of: required.union(optional)) ? names : []
    }

    static func integer(_ value: StrictJSONValue?) -> Int64? {
        guard case let .number(raw)? = value, !raw.contains("."),
              !raw.contains("e"),
              !raw.contains("E") else { return nil }
        return Int64(raw)
    }

    static func string(_ value: StrictJSONValue) throws -> String {
        guard case let .string(raw) = value
        else { throw mismatch }
        return raw
    }

    static func bool(_ value: StrictJSONValue) throws -> Bool {
        guard case let .bool(raw) = value
        else { throw mismatch }
        return raw
    }

    static func decimal(_ value: String) -> Bool {
        PropertyWireValidation.decimal(value)
    }

    static func timestamp(_ value: String) -> Bool {
        PropertyWireValidation.timestamp(value)
    }

    static func pageToken(_ value: StrictJSONValue?) throws -> String? {
        guard let value else { return nil }
        let raw = try string(value)
        guard PropertyWireValidation.token(raw) else { throw mismatch }
        return raw
    }
}

import VoyagerShared

public enum HistoricalConditionCompatibility {
    public struct Resolution: Equatable, Sendable {
        public let propertyKey: String
        public let propertyType: SystemPropertyTypeKey
        public let operatorCode: String
        public let valueContract: Condition.ValueContract
        public let isPathDerived: Bool

        public func normalizedPayload(from payload: SearchConditionPayload) -> SearchConditionPayload {
            SearchConditionPayload(
                propertyKey: propertyKey,
                operator: operatorCode,
                value: payload.value,
            )
        }
    }

    public static func resolution(
        for payload: SearchConditionPayload,
        canonicalPropertyKey: String? = nil,
        currentPropertyType: SystemPropertyTypeKey? = nil,
    ) -> Resolution? {
        let propertyKey = canonicalPropertyKey
            ?? legacyPropertyKeys[payload.propertyKey]
            ?? payload.propertyKey
        let rawOperator = payload.operator.lowercased()
        let operatorCode = normalizedOperatorCode(rawOperator)
        return retiredPathResolution(propertyKey: propertyKey, operatorCode: operatorCode)
            ?? coordinateResolution(
                propertyKey: propertyKey,
                operatorCode: operatorCode,
                value: payload.value,
            )
            ?? legacyInResolution(propertyKey: propertyKey, rawOperator: rawOperator)
            ?? categoricalMigrationResolution(
                propertyKey: propertyKey,
                rawOperator: rawOperator,
                operatorCode: operatorCode,
            )
            ?? currentTypeResolution(
                propertyKey: propertyKey,
                propertyType: currentPropertyType,
                operatorCode: operatorCode,
            )
    }
}

extension HistoricalConditionCompatibility {
    static func restoredCondition(
        from payload: SearchConditionPayload,
        canonicalPropertyKey: String?,
        currentPropertyType: SystemPropertyTypeKey?,
        registryClient: RegistryClient,
    ) -> Condition? {
        guard let resolution = resolution(
            for: payload,
            canonicalPropertyKey: canonicalPropertyKey,
            currentPropertyType: currentPropertyType,
        ),
            let values = ConditionCodec.decode(payload.value, contract: resolution.valueContract)
        else {
            return nil
        }

        let propertyKey = resolution.propertyKey
        let currentOperatorOptions = canonicalPropertyKey.map { key in
            registryClient.operatorCodes(for: key).map { code in
                Condition.OperatorOption(code: code, label: registryClient.operatorLabel(for: code))
            }
        } ?? []
        let operationCode = alphaListOperators.contains(payload.operator.lowercased())
            ? payload.operator.lowercased()
            : resolution.operatorCode
        let selectedOption = Condition.OperatorOption(
            code: operationCode,
            label: historicalOperatorLabels[resolution.operatorCode] ?? resolution.operatorCode,
        )
        let operatorOptions = currentOperatorOptions.contains(where: { $0.code == selectedOption.code })
            ? currentOperatorOptions
            : currentOperatorOptions + [selectedOption]
        let label = canonicalPropertyKey.map(registryClient.label(for:))
            ?? historicalPropertyLabels[propertyKey]
            ?? propertyKey

        return Condition(
            property: .init(
                key: propertyKey,
                label: label,
                type: resolution.propertyType,
                unitContract: canonicalPropertyKey
                    .flatMap { registryClient.unitSpec(for: $0) }
                    .flatMap(Condition.UnitContract.init),
                operatorOptions: operatorOptions,
            ),
            operation: .init(
                code: operationCode,
                label: selectedOption.label,
                valueContract: resolution.valueContract,
            ),
            values: values,
            availability: .available,
            opaqueSource: nil,
        )
    }
}

private extension HistoricalConditionCompatibility {
    static let numericOperators: Set<String> = ["eq", "neq", "gt", "gte", "lt", "lte", "btw", "nbtw"]
    static let scalarStringOperators: Set<String> = ["eq", "neq", "cn", "nc", "sw", "ew", "rx"]
    static let alphaListOperators: Set<String> = [
        "contains_any", "contains_all", "not_contains_any", "not_contains_all",
    ]
    static let changedCategoricalProperties: Set<String> = [
        "city",
        "country",
        "extension",
        "file_kind",
        "musical_genre",
        "musical_instrument_category",
        "tag_names",
        "uniform_type_identifier",
    ]
    static let stableStringListProperties: Set<String> = [
        "city",
        "country",
        "extension",
        "file_kind",
        "musical_genre",
        "musical_instrument_category",
        "uniform_type_identifier",
    ]
    static let retiredPathPropertyTypes: [String: SystemPropertyTypeKey] = [
        "depth_from_home": .number,
        "dir_path": .string,
        "parent_dir_name": .string,
        "relative_path_from_home": .string,
    ]
    static let legacyPropertyKeys: [String: String] = [
        "addedAt": "added_date",
        "audioBitRate": "audio_bit_rate",
        "audioChannelCount": "audio_channel_count",
        "audioSampleRate": "audio_sample_rate",
        "colorSpace": "color_space",
        "contentCreatedAt": "content_creation_date",
        "contentModifiedAt": "modification_date",
        "contentType": "uniform_type_identifier",
        "createdAt": "creation_date",
        "duration": "duration_seconds",
        "hasAlphaChannel": "has_alpha_channel",
        "isInvisible": "is_invisible",
        "kind": "file_kind",
        "lastUsedAt": "last_used_date",
        "modifiedAt": "modification_date",
        "name": "name_stem",
        "numberOfPages": "number_of_pages",
        "pixelHeight": "pixel_height",
        "pixelWidth": "pixel_width",
        "videoBitRate": "video_bit_rate",
    ]
    static let historicalPropertyLabels: [String: String] = [
        "depth_from_home": "Depth from Home",
        "dir_path": "Directory Path",
        "parent_dir_name": "Parent Directory Name",
        "relative_path_from_home": "Relative Path from Home",
    ]
    static let historicalOperatorLabels: [String: String] = [
        "all": "Contains all",
        "any": "Contains any",
        "cn": "Contains",
        "in": "In list",
        "miss": "Missing any",
        "neq": "Is not",
        "none": "Contains none",
        "sw": "Starts with",
    ]
    static let legacyOperatorCodes: [String: String] = [
        "between": "btw",
        "contains": "cn",
        "contains_all": "all",
        "contains_any": "any",
        "ends_with": "ew",
        "matches": "rx",
        "not_between": "nbtw",
        "not_contains_all": "miss",
        "not_contains_any": "none",
        "not_empty": "exists",
        "starts_with": "sw",
    ]

    static func normalizedOperatorCode(_ operatorCode: String) -> String {
        legacyOperatorCodes[operatorCode] ?? operatorCode
    }

    static func retiredPathResolution(
        propertyKey: String,
        operatorCode: String,
    ) -> Resolution? {
        guard let propertyType = retiredPathPropertyTypes[propertyKey] else { return nil }
        return makeResolution(
            propertyKey: propertyKey,
            propertyType: propertyType,
            operatorCode: operatorCode,
            isPathDerived: true,
        )
    }

    static func coordinateResolution(
        propertyKey: String,
        operatorCode: String,
        value: JSONValue?,
    ) -> Resolution? {
        guard ["latitude", "longitude"].contains(propertyKey),
              isNumericValue(value),
              numericOperators.contains(operatorCode)
        else {
            return nil
        }
        return makeResolution(propertyKey: propertyKey, propertyType: .number, operatorCode: operatorCode)
    }

    static func legacyInResolution(
        propertyKey: String,
        rawOperator: String,
    ) -> Resolution? {
        guard rawOperator == "in" else { return nil }
        if propertyKey == "audio_channel_count" {
            return Resolution(
                propertyKey: propertyKey,
                propertyType: .number,
                operatorCode: "in",
                valueContract: .init(shape: .list, count: .multiple, input: .listNumber),
                isPathDerived: false,
            )
        }
        if propertyKey == "color_space" {
            return makeResolution(propertyKey: propertyKey, propertyType: .stringList, operatorCode: "any")
        }
        guard changedCategoricalProperties.contains(propertyKey) else { return nil }
        return makeResolution(propertyKey: propertyKey, propertyType: .categorical, operatorCode: "any")
    }

    static func categoricalMigrationResolution(
        propertyKey: String,
        rawOperator: String,
        operatorCode: String,
    ) -> Resolution? {
        guard changedCategoricalProperties.contains(propertyKey) else { return nil }
        if alphaListOperators.contains(rawOperator) {
            return makeResolution(propertyKey: propertyKey, propertyType: .string, operatorCode: operatorCode)
        }
        if stableStringListProperties.contains(propertyKey), ["all", "miss"].contains(operatorCode) {
            return makeResolution(propertyKey: propertyKey, propertyType: .stringList, operatorCode: operatorCode)
        }
        guard scalarStringOperators.contains(operatorCode) else { return nil }
        return makeResolution(propertyKey: propertyKey, propertyType: .string, operatorCode: operatorCode)
    }

    static func currentTypeResolution(
        propertyKey: String,
        propertyType: SystemPropertyTypeKey?,
        operatorCode: String,
    ) -> Resolution? {
        if propertyType == .string, ["any", "all"].contains(operatorCode) {
            return makeResolution(propertyKey: propertyKey, propertyType: .string, operatorCode: operatorCode)
        }
        guard propertyType == .boolean, operatorCode == "neq" else { return nil }
        return makeResolution(propertyKey: propertyKey, propertyType: .boolean, operatorCode: operatorCode)
    }

    static func makeResolution(
        propertyKey: String,
        propertyType: SystemPropertyTypeKey,
        operatorCode: String,
        isPathDerived: Bool = false,
    ) -> Resolution? {
        guard let contract = valueContract(propertyType: propertyType, operatorCode: operatorCode) else {
            return nil
        }
        return Resolution(
            propertyKey: propertyKey,
            propertyType: propertyType,
            operatorCode: operatorCode,
            valueContract: contract,
            isPathDerived: isPathDerived,
        )
    }

    static func valueContract(
        propertyType: SystemPropertyTypeKey,
        operatorCode: String,
    ) -> Condition.ValueContract? {
        if ["empty", "exists"].contains(operatorCode) {
            return .init(shape: .none, count: .fixed(0), input: .none)
        }
        if ["any", "all", "none", "miss"].contains(operatorCode) {
            return .init(shape: .list, count: .multiple, input: .listText)
        }
        if ["btw", "nbtw"].contains(operatorCode) {
            return propertyType == .date
                ? .init(shape: .range, count: .fixed(2), input: .rangeDate)
                : .init(shape: .range, count: .fixed(2), input: .rangeNumber)
        }
        if propertyType == .number {
            return numericOperators.contains(operatorCode)
                ? .init(shape: .single, count: .fixed(1), input: .singleNumber)
                : nil
        }
        if propertyType == .date {
            return numericOperators.contains(operatorCode)
                ? .init(shape: .single, count: .fixed(1), input: .singleDate)
                : nil
        }
        if propertyType == .boolean {
            return ["eq", "neq"].contains(operatorCode)
                ? .init(shape: .single, count: .fixed(1), input: .toggle)
                : nil
        }
        return scalarStringOperators.contains(operatorCode)
            ? .init(shape: .single, count: .fixed(1), input: .singleText)
            : nil
    }

    static func isNumericValue(_ value: JSONValue?) -> Bool {
        switch value {
        case .number?: true
        case let .array(values)?: values.allSatisfy { if case .number = $0 { true } else { false } }
        default: false
        }
    }
}

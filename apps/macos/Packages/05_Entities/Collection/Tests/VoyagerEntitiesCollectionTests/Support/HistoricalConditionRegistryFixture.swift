@_spi(Testing)
@testable import VoyagerEntitiesCollection
import VoyagerShared

enum HistoricalConditionRegistryFixture {
    private struct Definition {
        let canonicalKey: String
        let label: String
        let type: SystemPropertyTypeKey
        let currentOperator: String
        let contract: Condition.ValueContract
    }

    static func makeClient() -> RegistryClient {
        RegistryClient(
            allProperties: { [] },
            labelForKey: { definition(for: $0)?.label ?? $0 },
            propertyTypeString: { definition(for: $0)?.type.rawValue ?? "unknown" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { definition(for: $0).map { [$0.currentOperator] } ?? [] },
            operatorDefinition: operatorDefinition,
            resolvePropertyKey: resolvePropertyKey,
            resolveCondition: resolveCondition,
        )
    }

    private static func operatorDefinition(_ code: String) -> OperatorDefinition {
        switch code {
        case "any":
            OperatorDefinition(uiLabel: "Contains any", uiValueKind: ["categorical": "listText"])
        case "eq":
            OperatorDefinition(
                uiLabel: "Is",
                uiValueKind: [
                    "string": "singleText",
                    "number": "singleNumber",
                    "boolean": "toggle",
                ],
            )
        default:
            OperatorDefinition(uiLabel: code, uiValueKind: ["string": "singleText"])
        }
    }

    private static func resolvePropertyKey(_ key: String) -> PropertyKeyResolution {
        if let definition = definition(for: key) {
            return key == definition.canonicalKey
                ? .canonical(key)
                : .legacy(original: key, normalized: definition.canonicalKey)
        }
        return .unknown(key)
    }

    private static func resolveCondition(
        propertyKey: String,
        operatorCode: String?,
        values: [String]?,
        sourcePayload: CollectionCondition?,
    ) -> Condition {
        let source = sourcePayload ?? CollectionCondition(
            propertyKey: propertyKey,
            operatorCode: operatorCode ?? "",
        )
        guard let definition = definition(for: propertyKey) else {
            return RegistryClient.opaqueCondition(
                key: propertyKey,
                source: source,
                availability: .unsupportedProperty,
            )
        }
        let property = Condition.Property(
            key: definition.canonicalKey,
            label: definition.label,
            type: definition.type,
            unitContract: nil,
            operatorOptions: [.init(code: definition.currentOperator, label: definition.currentOperator)],
        )
        guard let operatorCode else {
            return Condition(
                property: property,
                operation: nil,
                values: nil,
                availability: .available,
                opaqueSource: nil,
            )
        }
        guard operatorCode == definition.currentOperator else {
            return Condition(
                property: property,
                operation: nil,
                values: nil,
                availability: .unsupportedOperator,
                opaqueSource: source,
            )
        }
        return Condition(
            property: property,
            operation: .init(code: operatorCode, label: operatorCode, valueContract: definition.contract),
            values: values,
            availability: .available,
            opaqueSource: nil,
        )
    }

    private static func definition(for key: String) -> Definition? {
        switch key {
        case "contentType", "uniform_type_identifier": categorical("uniform_type_identifier", "Content Type")
        case "kind", "file_kind": categorical("file_kind", "Kind")
        case "extension": categorical("extension", "Extension")
        case "tag_names": categorical("tag_names", "Tags")
        case "audioChannelCount", "audio_channel_count": number("audio_channel_count", "Audio Channels")
        case "latitude": string("latitude", "Latitude")
        case "colorSpace", "color_space": string("color_space", "Color Space")
        case "isInvisible", "is_invisible": boolean("is_invisible", "Invisible")
        case "size": number("size", "Size")
        default: nil
        }
    }

    private static func categorical(_ key: String, _ label: String) -> Definition {
        Definition(
            canonicalKey: key,
            label: label,
            type: .categorical,
            currentOperator: "any",
            contract: .init(shape: .list, count: .multiple, input: .listText),
        )
    }

    private static func number(_ key: String, _ label: String) -> Definition {
        Definition(
            canonicalKey: key,
            label: label,
            type: .number,
            currentOperator: "eq",
            contract: .init(shape: .single, count: .fixed(1), input: .singleNumber),
        )
    }

    private static func string(_ key: String, _ label: String) -> Definition {
        Definition(
            canonicalKey: key,
            label: label,
            type: .string,
            currentOperator: "eq",
            contract: .init(shape: .single, count: .fixed(1), input: .singleText),
        )
    }

    private static func boolean(_ key: String, _ label: String) -> Definition {
        Definition(
            canonicalKey: key,
            label: label,
            type: .boolean,
            currentOperator: "eq",
            contract: .init(shape: .single, count: .fixed(1), input: .toggle),
        )
    }
}

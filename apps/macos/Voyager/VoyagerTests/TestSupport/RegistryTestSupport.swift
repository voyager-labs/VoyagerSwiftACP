import Foundation

#if canImport(Voyager)
@testable import Voyager

enum RegistryTestSupport {
    private static let registryLabels: [String: String] = [
        "name_full": "Name",
        "file_allocated_size": "Size",
    ]

    private static let registryOperatorDefinition = OperatorDefinition(
        uiLabel: "Equals",
        mdqueryOperator: nil as String?,
        valueShape: nil as ValueShape?,
        valueCount: nil as ValueCount?,
        allowedTypes: nil as [String]?,
        inverseOf: nil as String?,
        aliases: nil as [String]?,
        uiValueKind: [
            "string": "singleText",
            "number": "singleNumber",
            "date": "singleDate",
            "boolean": "toggle",
        ] as [String: String]?,
    )

    static func makeRegistryClient() -> RegistryClient {
        RegistryClient(
            allProperties: { [] },
            labelForKey: { registryLabels[$0] ?? $0 },
            propertyTypeString: registryPropertyType(for:),
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { _ in registryOperatorDefinition },
            operatorValueUIKind: { _, typeKey in registryUIKind(for: typeKey) },
            resolvePropertyKey: registryResolution(for:),
        )
    }

    private static func registryPropertyType(for key: String) -> String {
        switch key {
        case "file_allocated_size":
            "number"
        default:
            "string"
        }
    }

    private static func registryUIKind(for typeKey: String) -> String {
        switch typeKey {
        case "number":
            "singleNumber"
        case "date":
            "singleDate"
        case "boolean":
            "toggle"
        default:
            "singleText"
        }
    }

    private static func registryResolution(for key: String) -> PropertyKeyResolution {
        switch key {
        case "name_full":
            .canonical(key)
        case "file_allocated_size":
            .canonical(key)
        case "name":
            .legacy(original: key, normalized: "name_full")
        case "size":
            .legacy(original: key, normalized: "file_allocated_size")
        default:
            .unknown(key)
        }
    }
}

#endif

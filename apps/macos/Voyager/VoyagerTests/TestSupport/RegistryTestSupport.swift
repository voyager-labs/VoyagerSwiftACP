import Foundation

#if canImport(Voyager)
@testable import Voyager

enum RegistryTestSupport {
    private static let registrySnapshot = RegistrySnapshot.load()

    private static let registryLabels: [String: String] = [
        "name_full": "Name",
        "size": "File size",
        "file_allocated_size": "Size",
        "audio_bit_rate": "Audio bit rate",
        "video_bit_rate": "Video bit rate",
        "total_bit_rate": "Total bit rate",
    ]

    private static let registryUnitSpecs: [String: SystemPropertyUnitSpec] = registrySnapshot.propertyKeyToUnitSpec

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
            propertyTypeString: propertyTypeString(for:),
            propertyUnitSpec: { registryUnitSpecs[$0] },
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { _ in registryOperatorDefinition },
            operatorValueUIKind: { _, typeKey in registryUIKind(for: typeKey) },
            resolvePropertyKey: registryResolution(for:),
        )
    }

    static func propertyTypeString(for key: String) -> String {
        switch key {
        case "size":
            "number"
        case "file_allocated_size":
            "number"
        case "audio_bit_rate", "video_bit_rate", "total_bit_rate":
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
        case "size":
            .canonical(key)
        case "file_allocated_size":
            .canonical(key)
        case "audio_bit_rate", "video_bit_rate", "total_bit_rate":
            .canonical(key)
        case "name":
            .legacy(original: key, normalized: "name_full")
        default:
            .unknown(key)
        }
    }
}

#endif

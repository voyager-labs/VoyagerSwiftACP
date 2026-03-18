import Foundation

#if canImport(Voyager)
@testable import Voyager

enum RegistryTestSupport {
    private static let bitRateUnitSpec = SystemPropertyUnitSpec(
        canonicalUnit: "bps",
        units: [
            .init(code: "bps", label: "bps", factorToCanonical: "1"),
            .init(code: "Kbps", label: "Kbps", factorToCanonical: "1000"),
            .init(code: "Mbps", label: "Mbps", factorToCanonical: "1000000"),
        ],
        defaultDisplayUnit: "bps",
    )

    private static let byteSizeUnitSpec = SystemPropertyUnitSpec(
        canonicalUnit: "B",
        units: [
            .init(code: "B", label: "Byte", factorToCanonical: "1"),
            .init(code: "KB", label: "KB", factorToCanonical: "1024"),
            .init(code: "MB", label: "MB", factorToCanonical: "1048576"),
            .init(code: "GB", label: "GB", factorToCanonical: "1073741824"),
        ],
        defaultDisplayUnit: "Byte",
    )

    private static let registryLabels: [String: String] = [
        "name_full": "Name",
        "size": "File size",
        "file_allocated_size": "Size",
        "audio_bit_rate": "Audio bit rate",
        "video_bit_rate": "Video bit rate",
        "total_bit_rate": "Total bit rate",
    ]

    private static let registryUnitSpecs: [String: SystemPropertyUnitSpec] = [
        "size": byteSizeUnitSpec,
        "file_allocated_size": byteSizeUnitSpec,
        "audio_bit_rate": bitRateUnitSpec,
        "video_bit_rate": bitRateUnitSpec,
        "total_bit_rate": bitRateUnitSpec,
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

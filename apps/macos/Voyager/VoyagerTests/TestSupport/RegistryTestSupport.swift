import Foundation

#if canImport(Voyager)
@testable import Voyager
@testable import VoyagerEntitiesEntry

@MainActor
enum RegistryTestSupport {
    private static let registryLabels: [String: String] = [
        "name_full": "Name",
        "size": "File size",
        "audio_bit_rate": "Audio bit rate",
        "video_bit_rate": "Video bit rate",
        "total_bit_rate": "Total bit rate",
    ]

    private static let registryOperatorDefinition = VoyagerEntitiesEntry.OperatorDefinition(
        uiLabel: "Equals",
        mdqueryOperator: nil as String?,
        valueShape: nil as VoyagerEntitiesEntry.ValueShape?,
        valueCount: nil as VoyagerEntitiesEntry.ValueCount?,
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

    static func makeRegistryClient() -> VoyagerEntitiesEntry.RegistryClient {
        let labels = registryLabels
        let unitSpecs = registryUnitSpecs()
        let opDef = registryOperatorDefinition

        return VoyagerEntitiesEntry.RegistryClient(
            allProperties: { [] },
            labelForKey: { labels[$0] ?? $0 },
            propertyTypeString: propertyTypeString(for:),
            propertyUnitSpec: { unitSpecs[$0] },
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { _ in opDef },
            operatorValueUIKind: { _, typeKey in registryUIKind(for: typeKey) },
            resolvePropertyKey: registryResolution(for:),
        )
    }

    nonisolated static func propertyTypeString(for key: String) -> String {
        switch key {
        case "size":
            "number"
        case "audio_bit_rate", "video_bit_rate", "total_bit_rate":
            "number"
        default:
            "string"
        }
    }

    private static func registrySnapshot() -> VoyagerEntitiesEntry.RegistrySnapshot {
        MainActor.assumeIsolated {
            VoyagerEntitiesEntry.RegistrySnapshot.load()
        }
    }

    private nonisolated static func registryUnitSpecs() -> [String: VoyagerEntitiesEntry.SystemPropertyUnitSpec] {
        MainActor.assumeIsolated {
            registrySnapshot().propertyKeyToUnitSpec
        }
    }

    private nonisolated static func registryUIKind(for typeKey: String) -> String {
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

    private nonisolated static func registryResolution(for key: String) -> VoyagerEntitiesEntry.PropertyKeyResolution {
        switch key {
        case "name_full":
            .canonical(key)
        case "size":
            .canonical(key)
        case "file_allocated_size":
            .legacy(original: key, normalized: "size")
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

import Foundation

enum HistoricalCollectionReleaseFixture {
    enum SchemaEncoding {
        case legacyInt
        case versionObject
    }

    struct ReleaseCase {
        let tag: String
        let schemaEncoding: SchemaEncoding
        let excludedScopes: [String]?
        let includeSubfolders: Bool?
        let includeDirectories: Bool?
        let includesLegacyViewState: Bool

        func encodedPayload() throws -> Data {
            let schemaVersion: Any = switch schemaEncoding {
            case .legacyInt: 1
            case .versionObject: ["major": 1, "minor": 0]
            }
            var payload: [String: Any] = [
                "schemaVersion": schemaVersion,
                "id": "historical-\(tag)",
                "name": "Historical \(tag)",
                "createdAt": Date(timeIntervalSince1970: 1_700_000_000),
                "updatedAt": Date(timeIntervalSince1970: 1_700_000_100),
                "query": "report",
                "scopes": ["/VoyagerFixtures/Documents"],
                "conditions": [],
                "appVersion": tag,
            ]
            if let excludedScopes {
                payload["excludedScopes"] = excludedScopes
            }
            if let includeSubfolders {
                payload["includeSubfolders"] = includeSubfolders
            }
            if let includeDirectories {
                payload["includeDirectories"] = includeDirectories
            }
            if includesLegacyViewState {
                payload["sortKey"] = "name"
                payload["sortOrder"] = "ascending"
                payload["viewLayout"] = "list"
            }
            return try PropertyListSerialization.data(
                fromPropertyList: payload,
                format: .binary,
                options: 0,
            )
        }
    }

    static let all: [ReleaseCase] =
        legacyIntTags.map {
            ReleaseCase(
                tag: $0,
                schemaEncoding: .legacyInt,
                excludedScopes: nil,
                includeSubfolders: nil,
                includeDirectories: nil,
                includesLegacyViewState: $0 != "v0.3.0",
            )
        } + [
            ReleaseCase(
                tag: "v0.4.0",
                schemaEncoding: .versionObject,
                excludedScopes: nil,
                includeSubfolders: nil,
                includeDirectories: nil,
                includesLegacyViewState: false,
            ),
            ReleaseCase(
                tag: "v0.5.0",
                schemaEncoding: .versionObject,
                excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
                includeSubfolders: false,
                includeDirectories: nil,
                includesLegacyViewState: false,
            ),
        ] + currentDefinitionTags.map {
            ReleaseCase(
                tag: $0,
                schemaEncoding: .versionObject,
                excludedScopes: ["/VoyagerFixtures/Documents/Archive"],
                includeSubfolders: false,
                includeDirectories: true,
                includesLegacyViewState: false,
            )
        }

    private static let legacyIntTags = [
        "v0.0.1", "v0.0.2", "v0.0.3", "v0.0.4",
        "v0.1.0-alpha.1", "v0.1.0-alpha.2", "v0.1.0-alpha.3",
        "v0.1.0", "v0.1.1", "v0.1.2",
        "v0.2.0", "v0.2.1", "v0.2.2", "v0.3.0",
    ]

    private static let currentDefinitionTags = [
        "v0.6.0",
        "v0.7.0", "v0.7.1", "v0.7.2", "v0.7.3",
        "v0.8.0", "v0.8.1", "v0.8.2", "v0.8.3",
    ]
}

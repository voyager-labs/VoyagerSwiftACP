import Foundation

struct SystemPropertyRegistry: Decodable {
    let version: String?
    let categories: [String: [String: SystemPropertyDefinition]]

    struct SystemPropertyDefinition: Decodable {
        let uiLabel: String?
        let description: String
        let type: String
        let searchAliases: [String]?
        let systemKeys: [String]
        let availability: String?
        let valueFormat: String?
        let uiPinned: Bool?

        private enum CodingKeys: String, CodingKey {
            case uiLabel = "ui_label"
            case description
            case type
            case searchAliases = "search_aliases"
            case systemKeys = "system_keys"
            case availability
            case valueFormat = "value_format"
            case uiPinned = "ui_pinned"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version = "$version"
        case categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        categories =
            try container.decodeIfPresent([String: [String: SystemPropertyDefinition]].self, forKey: .categories)
                ?? [:]
    }
}

enum SystemPropertyRegistryLoader {
    enum LoadError: Error {
        case resourceURLNotFound
        case decodeFailed(path: String)
    }

    private static let registryFileName = "system_property_registry"
    private static let registryFileExtension = "json"

    static func load(
        bundle: Bundle = .main,
        environment _: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> SystemPropertyRegistry {
        guard let bundleURL = bundle.url(
            forResource: registryFileName,
            withExtension: registryFileExtension,
        ) else {
            throw LoadError.resourceURLNotFound
        }

        return try decodeRegistry(from: bundleURL)
    }

    private static func decodeRegistry(from url: URL) throws -> SystemPropertyRegistry {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(SystemPropertyRegistry.self, from: data)
        } catch {
            throw LoadError.decodeFailed(path: url.path)
        }
    }
}

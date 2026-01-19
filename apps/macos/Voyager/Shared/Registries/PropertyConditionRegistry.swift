import Foundation

struct PropertyConditionRegistry: Decodable {
    let version: String?
    let typeDefaults: [String: [String]]
    let operators: [String: OperatorDefinition]

    struct OperatorDefinition: Decodable {
        let uiLabel: String?
        let valueShape: ValueShape?
        let valueCount: ValueCount?
        let allowedTypes: [String]?
        let inverseOf: String?
        let aliases: [String]?
        let uiValueKind: [String: String]?

        private enum CodingKeys: String, CodingKey {
            case uiLabel = "ui_label"
            case valueShape = "value_shape"
            case valueCount = "value_count"
            case allowedTypes = "allowed_types"
            case inverseOf = "inverse_of"
            case aliases
            case uiValueKind = "ui_value_kind"
        }
    }

    enum ValueShape: String, Decodable {
        case none
        case single
        case list
        case range
    }

    enum ValueCount: Decodable, Equatable {
        case fixed(Int)
        case multiple

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .fixed(intValue)
                return
            }
            let text = try container.decode(String.self)
            if text == "n" {
                self = .multiple
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported value_count: \(text)",
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version = "$version"
        case typeDefaults = "type_defaults"
        case operators
    }
}

enum PropertyConditionRegistryLoader {
    enum LoadError: Error {
        case resourceURLNotFound
        case decodeFailed(path: String)
    }

    private static let registryFileName = "property_condition_registry"
    private static let registryFileExtension = "json"

    static func load(
        bundle: Bundle = .main,
        environment _: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> PropertyConditionRegistry {
        guard let bundleURL = bundle.url(
            forResource: registryFileName,
            withExtension: registryFileExtension,
        ) else {
            throw LoadError.resourceURLNotFound
        }

        return try decodeRegistry(from: bundleURL)
    }

    private static func decodeRegistry(from url: URL) throws -> PropertyConditionRegistry {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(PropertyConditionRegistry.self, from: data)
        } catch {
            throw LoadError.decodeFailed(path: url.path)
        }
    }
}

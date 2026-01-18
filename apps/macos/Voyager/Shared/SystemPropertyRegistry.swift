import Foundation

struct SystemPropertyRegistry: Decodable {
    let version: String?
    let propertyKeyRegistry: [String: PropertyKeyDefinition]

    struct PropertyKeyDefinition: Decodable {
        let propertyKey: String?
        let valueType: String
        let supportedOperators: [String]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case propertyKeyRegistry
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        propertyKeyRegistry =
            try container.decodeIfPresent([String: PropertyKeyDefinition].self, forKey: .propertyKeyRegistry)
                ?? [:]
    }
}

enum SystemPropertyRegistryLoader {
    enum LoadError: Error {
        case resourceURLNotFound
        case projectRootNotFound
        case fileNotFound(path: String)
        case decodeFailed(path: String)
    }

    private static let registryFileName = "system_property_registry"
    private static let registryFileExtension = "json"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) throws -> SystemPropertyRegistry {
        if let resourceURL = bundle.url(
            forResource: registryFileName,
            withExtension: registryFileExtension,
        ) {
            return try decodeRegistry(from: resourceURL)
        }

        let projectRoot = resolveProjectRoot(environment: environment)
        guard let projectRoot else {
            throw LoadError.projectRootNotFound
        }

        let fileURL = projectRoot
            .appendingPathComponent("shared")
            .appendingPathComponent("\(registryFileName).\(registryFileExtension)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LoadError.fileNotFound(path: fileURL.path)
        }

        return try decodeRegistry(from: fileURL)
    }

    private static func resolveProjectRoot(
        environment: [String: String],
    ) -> URL? {
        if let envRoot = environment["VOYAGER_PROJECT_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot)
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return EnvironmentLoader.BackendMode.inferProjectRoot(from: current)
    }

    private static func decodeRegistry(from url: URL) throws -> SystemPropertyRegistry {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(SystemPropertyRegistry.self, from: data)
        } catch {
            throw LoadError.decodeFailed(path: url.path)
        }
    }
}

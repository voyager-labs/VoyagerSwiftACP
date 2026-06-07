import Foundation

nonisolated enum RegistryLoader {
    enum LoadError: Error {
        case resourceURLNotFound(name: String, fileExtension: String)
        case decodeFailed(path: String, type: String)
    }

    nonisolated static func load<T: Decodable>(
        resourceName: String,
        fileExtension: String = "json",
        bundle: Bundle = .main,
    ) throws -> T {
        guard let bundleURL = bundle.url(
            forResource: resourceName,
            withExtension: fileExtension,
        ) else {
            throw LoadError.resourceURLNotFound(name: resourceName, fileExtension: fileExtension)
        }

        do {
            let data = try Data(contentsOf: bundleURL)
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LoadError.decodeFailed(path: bundleURL.path, type: String(describing: T.self))
        }
    }
}

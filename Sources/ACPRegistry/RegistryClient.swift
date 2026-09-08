import Foundation

// MARK: - Registry Client

public actor RegistryClient {
    /// Default registry CDN URL
    public static let defaultURL = URL(string: "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json")!

    private let registryURL: URL
    private let session: URLSession
    private let cacheDirectory: URL?

    private var cachedRegistry: Registry?
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval

    // MARK: - Initialization

    public init(
        registryURL: URL = RegistryClient.defaultURL,
        session: URLSession = .shared,
        cacheDirectory: URL? = nil,
        cacheDuration: TimeInterval = 3600, // 1 hour default
    ) {
        self.registryURL = registryURL
        self.session = session
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory
        self.cacheDuration = cacheDuration
    }

    private static var defaultCacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ACPRegistry", isDirectory: true)
    }

    // MARK: - Public API

    /// Fetches the registry, using cache if available and not expired
    public func fetch(forceRefresh: Bool = false) async throws -> Registry {
        // Check memory cache first
        if !forceRefresh, let cached = cachedRegistry, let lastFetch = lastFetchTime {
            if Date().timeIntervalSince(lastFetch) < cacheDuration {
                return cached
            }
        }

        // Check disk cache
        if !forceRefresh, let diskCached = try? loadFromDisk() {
            cachedRegistry = diskCached
            lastFetchTime = Date()
            return diskCached
        }

        // Fetch from network
        let registry = try await fetchFromNetwork()
        cachedRegistry = registry
        lastFetchTime = Date()

        // Save to disk cache
        try? saveToDisk(registry)

        return registry
    }

    /// Returns a specific agent by ID
    public func agent(id: String) async throws -> RegistryAgent? {
        let registry = try await fetch()
        return registry.agents.first { $0.id == id }
    }

    /// Returns all agents
    public func agents() async throws -> [RegistryAgent] {
        let registry = try await fetch()
        return registry.agents
    }

    /// Returns all extensions
    public func extensions() async throws -> [RegistryAgent] {
        let registry = try await fetch()
        return registry.extensions
    }

    /// Clears all caches
    public func clearCache() {
        cachedRegistry = nil
        lastFetchTime = nil

        if let cacheFile = cacheFileURL {
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }

    // MARK: - Private Methods

    private func fetchFromNetwork() async throws -> Registry {
        let (data, response) = try await session.data(from: registryURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RegistryError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw RegistryError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Registry.self, from: data)
        } catch {
            throw RegistryError.decodingError(error)
        }
    }

    private var cacheFileURL: URL? {
        cacheDirectory?.appendingPathComponent("registry.json")
    }

    private func loadFromDisk() throws -> Registry? {
        guard let cacheFile = cacheFileURL else { return nil }

        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // Check if cache file is expired
        let attributes = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
        if let modificationDate = attributes[.modificationDate] as? Date {
            if Date().timeIntervalSince(modificationDate) > cacheDuration {
                return nil
            }
        }

        let data = try Data(contentsOf: cacheFile)
        return try JSONDecoder().decode(Registry.self, from: data)
    }

    private func saveToDisk(_ registry: Registry) throws {
        guard let cacheFile = cacheFileURL, let cacheDir = cacheDirectory else { return }

        // Ensure cache directory exists
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(registry)
        try data.write(to: cacheFile)
    }
}

// MARK: - Errors

public enum RegistryError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case agentNotFound(String)
    case unsupportedPlatform
    case downloadFailed(Error)
    case extractionFailed(Error)
    case invalidIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from registry"
        case let .httpError(statusCode):
            "HTTP error: \(statusCode)"
        case let .decodingError(error):
            "Failed to decode registry: \(error.localizedDescription)"
        case let .agentNotFound(id):
            "Agent not found: \(id)"
        case .unsupportedPlatform:
            "No distribution available for this platform"
        case let .downloadFailed(error):
            "Download failed: \(error.localizedDescription)"
        case let .extractionFailed(error):
            "Extraction failed: \(error.localizedDescription)"
        case let .invalidIdentifier(identifier):
            "Agent identifier escapes the install directory: '\(identifier)'"
        }
    }
}

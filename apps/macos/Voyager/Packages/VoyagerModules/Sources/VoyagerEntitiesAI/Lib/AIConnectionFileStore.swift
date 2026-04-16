import Darwin
import Foundation

public actor AIConnectionFileStore {
    private let fileManager: FileManager
    private let payloadURL: URL
    private let lockURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        fileManager: FileManager = .default,
        payloadURL: URL,
        lockURL: URL,
    ) {
        self.fileManager = fileManager
        self.payloadURL = payloadURL
        self.lockURL = lockURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func load() throws -> AIConnectionsFile {
        try withExclusiveLock {
            guard fileManager.fileExists(atPath: payloadURL.path) else {
                return AIConnectionsFile.empty()
            }

            let data = try Data(contentsOf: payloadURL)
            guard !data.isEmpty else {
                try quarantineAndRemove()
                return AIConnectionsFile.empty()
            }

            let file: AIConnectionsFile
            do {
                file = try decoder.decode(AIConnectionsFile.self, from: data)
            } catch {
                try quarantineAndRemove()
                return AIConnectionsFile.empty()
            }

            return AIConnectionsNormalizer.normalize(file)
        }
    }

    public func write(_ file: AIConnectionsFile) throws {
        try withExclusiveLock {
            try ensureParentDirectoryExists()
            let data = try encoder.encode(file)
            try data.write(to: payloadURL, options: .atomic)
        }
    }

    public func deleteCredential(for provider: AIProvider) throws {
        try withExclusiveLock {
            let current: AIConnectionsFile
            if fileManager.fileExists(atPath: payloadURL.path) {
                let data = try Data(contentsOf: payloadURL)
                do {
                    current = try decoder.decode(AIConnectionsFile.self, from: data)
                } catch {
                    try quarantineAndRemove()
                    return
                }
            } else {
                current = AIConnectionsFile.empty()
            }

            guard var record = current.providers[provider.rawValue] else { return }

            let updatedRecord = ProviderRecordFile(
                providerId: record.providerId,
                authMethod: record.authMethod,
                credential: nil,
                snapshot: ProviderSnapshotFile(
                    lastKnownStatus: .notVerified,
                    lastVerifiedAtMs: nil,
                    lastErrorCode: .none,
                ),
            )

            var updatedProviders = current.providers
            updatedProviders[provider.rawValue] = updatedRecord

            var updatedLastUsed = current.lastUsedProviderId
            var updatedLastUsedAt = current.lastUsedAtMs
            if updatedLastUsed == provider {
                updatedLastUsed = nil
                updatedLastUsedAt = nil
            }

            let updatedFile = AIConnectionsFile(
                schemaVersion: current.schemaVersion,
                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                lastUsedProviderId: updatedLastUsed,
                lastUsedAtMs: updatedLastUsedAt,
                providers: updatedProviders,
            )

            try ensureParentDirectoryExists()
            let data = try encoder.encode(updatedFile)
            try data.write(to: payloadURL, options: .atomic)
        }
    }

    private func quarantineAndRemove() throws {
        let quarantineURL = AIConnectionFSLocation.quarantineFileURL(
            directoryURL: payloadURL.deletingLastPathComponent(),
        )
        try ensureParentDirectoryExists()

        if fileManager.fileExists(atPath: payloadURL.path) {
            let data = try Data(contentsOf: payloadURL)
            try data.write(to: quarantineURL, options: .atomic)
            try fileManager.removeItem(at: payloadURL)
        }
    }

    private func ensureParentDirectoryExists() throws {
        let parent = payloadURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try ensureParentDirectoryExists()
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXLockError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXLockError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

public enum POSIXLockError: Error, Equatable {
    case openFailed(Int32)
    case lockFailed(Int32)
}

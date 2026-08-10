import Foundation

public typealias RuntimeStateMigrator = @Sendable (Data, Int) throws -> RuntimeStoredState

public actor RuntimeFileStateStore: RuntimeStateStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let migrator: RuntimeStateMigrator?

    public init(fileURL: URL, migrator: RuntimeStateMigrator? = nil) {
        self.fileURL = fileURL
        self.migrator = migrator
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() async throws -> RuntimeStoredState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try readSnapshotData()
        let version: Int
        do {
            version = try schemaVersion(in: data)
        } catch {
            try quarantineCorruptedSnapshot()
            throw RuntimeHostError.persistenceFailure
        }
        if version > RuntimeStoredState.currentSchemaVersion {
            throw RuntimeHostError.unsupportedSchemaVersion(version)
        }
        if version < RuntimeStoredState.currentSchemaVersion {
            return try migrate(data, from: version)
        }
        do {
            return try decode(data)
        } catch {
            try quarantineCorruptedSnapshot()
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func readSnapshotData() throws -> Data {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= RuntimeBoundaryLimits.snapshotBytes
        else { throw RuntimeHostError.persistenceFailure }
        do { return try Data(contentsOf: fileURL) } catch {
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func schemaVersion(in data: Data) throws -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schema_version"] as? Int
        else { throw RuntimeHostError.persistenceFailure }
        return version
    }

    private func migrate(_ data: Data, from version: Int) throws -> RuntimeStoredState {
        guard let migrator else { throw RuntimeHostError.migrationUnavailable(version) }
        do { return try migrator(data, version).validatedForRuntime()
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.migrationFailed
        }
    }

    private func decode(_ data: Data) throws -> RuntimeStoredState {
        do { return try decoder.decode(RuntimeStoredState.self, from: data).validatedForRuntime()
        } catch let error as RuntimeHostError {
            throw error
        } catch { throw RuntimeHostError.persistenceFailure }
    }

    private func quarantineCorruptedSnapshot() throws {
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        do {
            if FileManager.default.fileExists(atPath: quarantineURL.path) {
                _ = try FileManager.default.replaceItemAt(quarantineURL, withItemAt: fileURL)
            } else {
                try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: quarantineURL.path,
            )
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
    }

    public func save(_ state: RuntimeStoredState) async throws {
        do {
            let data = try encoder.encode(state.validatedForRuntime())
            guard data.count <= RuntimeBoundaryLimits.snapshotBytes else {
                throw RuntimeHostError.persistenceFailure
            }
            try replaceSnapshot(with: data)
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func replaceSnapshot(with data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try setPermissions(0o700, at: directory)

        let temporaryURL = directory
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL, options: .atomic)
        try setPermissions(0o600, at: temporaryURL)
        try ensureSnapshotPlaceholderExists()
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        try setPermissions(0o600, at: fileURL)
    }

    private func ensureSnapshotPlaceholderExists() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let didCreateFile = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(),
            attributes: [.posixPermissions: NSNumber(value: 0o600)],
        )
        guard didCreateFile else { throw RuntimeHostError.persistenceFailure }
    }

    private func setPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path,
        )
    }
}

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
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: fileURL, options: .atomic)
        } catch let error as RuntimeHostError {
            throw error
        } catch {
            throw RuntimeHostError.persistenceFailure
        }
    }
}

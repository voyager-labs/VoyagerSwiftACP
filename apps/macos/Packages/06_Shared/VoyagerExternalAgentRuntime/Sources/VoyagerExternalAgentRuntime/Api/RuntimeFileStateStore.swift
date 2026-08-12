@preconcurrency import Darwin
import Foundation

public typealias RuntimeStateMigrator = @Sendable (Data, Int) throws -> RuntimeStoredState

public actor RuntimeFileStateStore: RuntimeStateStore, RuntimeStateStoreHostMutation {
    private enum SnapshotReadError: Error {
        case oversized
    }

    private let fileURL: URL
    private let lockURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let migrator: RuntimeStateMigrator?

    public init(fileURL: URL, migrator: RuntimeStateMigrator? = nil) {
        self.fileURL = fileURL
        lockURL = fileURL.appendingPathExtension("lock")
        self.migrator = migrator
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() async throws -> RuntimeStoredState? {
        try await withExclusiveLock {
            try loadUnlocked()
        }
    }

    private func loadUnlocked() throws -> RuntimeStoredState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try readSnapshotData()
        } catch SnapshotReadError.oversized {
            try quarantineCorruptedSnapshot()
            throw RuntimeHostError.persistenceFailure
        }
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
            do {
                return try migrate(data, from: version)
            } catch let error as RuntimeHostError where error == .migrationUnavailable(version) {
                throw error
            } catch {
                try quarantineCorruptedSnapshot()
                throw error
            }
        }
        do {
            return try decode(data)
        } catch {
            try quarantineCorruptedSnapshot()
            throw RuntimeHostError.persistenceFailure
        }
    }

    private func readSnapshotData() throws -> Data {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw RuntimeHostError.persistenceFailure
        }
        guard size <= RuntimeBoundaryLimits.snapshotBytes else { throw SnapshotReadError.oversized }
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
        try await withExclusiveLock {
            try saveUnlocked(state)
        }
    }

    func updateHost(
        _ host: ExternalAgentSessionReference,
        expected: RuntimeStoredSession?,
        replacement: RuntimeStoredSession?,
    ) async throws -> RuntimeStoredState {
        try await withExclusiveLock {
            let current = try loadUnlocked() ?? RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: [],
            )
            guard current.sessions.first(where: {
                $0.externalAgentSessionReference == host
            }) == expected else { throw RuntimeHostError.persistenceFailure }
            var sessions = Dictionary(uniqueKeysWithValues: current.sessions.map {
                ($0.externalAgentSessionReference, $0)
            })
            sessions[host] = replacement
            let updated = RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: sessions.values.sorted {
                    $0.externalAgentSessionReference.rawValue
                        < $1.externalAgentSessionReference.rawValue
                },
            )
            try saveUnlocked(updated)
            return updated
        }
    }

    private func saveUnlocked(_ state: RuntimeStoredState) throws {
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
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw RuntimeHostError.persistenceFailure
            }
            return
        }
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

    private func withExclusiveLock<T>(_ operation: () throws -> T) async throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try setPermissions(0o700, at: directory)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RuntimeHostError.persistenceFailure }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else { throw RuntimeHostError.persistenceFailure }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try operation()
    }
}

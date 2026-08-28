@preconcurrency import Darwin
import Foundation

public actor RuntimeFileStateStore: RuntimeStateStore {
    private enum SnapshotReadError: Error {
        case oversized
    }

    private let fileURL: URL
    private let lockURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    public init(fileURL: URL) {
        self.fileURL = fileURL
        lockURL = fileURL.appendingPathExtension("lock")
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
            throw RuntimeStateStoreError.invalidSnapshot
        }
        let version: Int
        do {
            version = try schemaVersion(in: data)
        } catch {
            try quarantineCorruptedSnapshot()
            throw RuntimeStateStoreError.invalidSnapshot
        }
        if version > RuntimeStoredState.currentSchemaVersion {
            throw RuntimeStateStoreError.unsupportedSchemaVersion(version)
        }
        if version < RuntimeStoredState.currentSchemaVersion {
            throw RuntimeStateStoreError.unsupportedSchemaVersion(version)
        }
        do {
            return try decode(data)
        } catch let error as RuntimeStateStoreError {
            try quarantineCorruptedSnapshot()
            throw error
        } catch {
            try quarantineCorruptedSnapshot()
            throw RuntimeStateStoreError.unavailable
        }
    }

    private func readSnapshotData() throws -> Data {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw RuntimeStateStoreError.unavailable
        }
        guard size <= RuntimeBoundaryLimits.snapshotBytes else { throw SnapshotReadError.oversized }
        do { return try Data(contentsOf: fileURL) } catch {
            throw RuntimeStateStoreError.unavailable
        }
    }

    private func schemaVersion(in data: Data) throws -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schema_version"] as? Int
        else { throw RuntimeStateStoreError.invalidSnapshot }
        return version
    }

    private func decode(_ data: Data) throws -> RuntimeStoredState {
        do { return try decoder.decode(RuntimeStoredState.self, from: data).validatedForRuntime()
        } catch let error as RuntimeStateStoreError {
            throw error
        } catch { throw RuntimeStateStoreError.invalidSnapshot }
    }

    private func quarantineCorruptedSnapshot() throws {
        let quarantineURL = fileURL.appendingPathExtension("corrupt")
        do {
            if FileManager.default.fileExists(atPath: quarantineURL.path) {
                try FileManager.default.removeItem(at: quarantineURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: quarantineURL.path,
            )
        } catch {
            throw RuntimeStateStoreError.unavailable
        }
    }

    public func apply(_ mutation: RuntimeStateMutation) async throws -> RuntimeStateMutationResult {
        try await withExclusiveLock {
            guard mutation.host.rawValue.isRuntimeBounded,
                  mutation.expected?.externalAgentSessionReference == nil || mutation.expected?
                  .externalAgentSessionReference == mutation.host,
                  mutation.replacement?.externalAgentSessionReference == nil || mutation.replacement?
                  .externalAgentSessionReference == mutation.host
            else { throw RuntimeStateStoreError.invalidSnapshot }
            let loaded = try loadUnlocked()
            let current = loaded ?? RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: [],
            )
            let currentSession = current.sessions.first { $0.externalAgentSessionReference == mutation.host }
            guard currentSession == mutation.expected else {
                return .conflict(loaded)
            }
            if let replacement = mutation.replacement,
               current.sessions.contains(where: {
                   $0.externalAgentSessionReference != mutation.host && $0.runReference == replacement.runReference
               })
            {
                return .conflict(loaded)
            }
            var sessions = Dictionary(uniqueKeysWithValues: current.sessions.map {
                ($0.externalAgentSessionReference, $0)
            })
            sessions[mutation.host] = mutation.replacement
            let updated = RuntimeStoredState(
                schemaVersion: RuntimeStoredState.currentSchemaVersion,
                sessions: sessions.values.sorted {
                    $0.externalAgentSessionReference.rawValue
                        < $1.externalAgentSessionReference.rawValue
                },
            )
            if updated != current {
                try saveUnlocked(updated)
            }
            return .committed(updated)
        }
    }

    private func saveUnlocked(_ state: RuntimeStoredState) throws {
        do {
            let data = try encoder.encode(state.validatedForRuntime())
            guard data.count <= RuntimeBoundaryLimits.snapshotBytes else {
                throw RuntimeStateStoreError.unavailable
            }
            try replaceSnapshot(with: data)
        } catch let error as RuntimeStateStoreError {
            throw error
        } catch {
            throw RuntimeStateStoreError.unavailable
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
                throw RuntimeStateStoreError.unavailable
            }
            return
        }
        let didCreateFile = FileManager.default.createFile(
            atPath: fileURL.path,
            contents: Data(),
            attributes: [.posixPermissions: NSNumber(value: 0o600)],
        )
        guard didCreateFile else { throw RuntimeStateStoreError.unavailable }
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
        guard descriptor >= 0 else { throw RuntimeStateStoreError.unavailable }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else { throw RuntimeStateStoreError.unavailable }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try operation()
    }
}

import Darwin
import Foundation

extension Notification.Name {
    static let voyagerHelperExternalFSDidUpdate = Notification.Name("voyagerHelperExternalFSDidUpdate")
    static let voyagerHelperExternalFSReplayRequest = Notification.Name("voyagerHelperExternalFSReplayRequest")
    static let voyagerHelperExternalFSReplayDidUpdate = Notification.Name("voyagerHelperExternalFSReplayDidUpdate")
}

nonisolated enum HelperExternalFileChangeUserInfoKey {
    static let schemaVersion = "schema_version"
    static let generatedAt = "generated_at"
    static let paths = "paths"
    static let consume = "consume"
}

nonisolated enum HelperExternalFSLocation {
    static let directoryName = "Voyager"
    static let payloadFileName = "helper_external_file_changes.json"
    static let lockFileName = "helper_external_file_changes.lock"
    static let quarantinePrefix = "helper_external_file_changes.corrupted"

    static func applicationSupportRootURL(homeDirectoryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser) -> URL
    {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    static func directoryURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupportRootURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func payloadFileURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL).appendingPathComponent(payloadFileName)
    }

    static func lockFileURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL).appendingPathComponent(lockFileName)
    }

    static func quarantineFileURL(
        directoryURL: URL,
        generatedAt: Date = Date(),
    ) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL
            .appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
    }
}

nonisolated struct HelperExternalFileChangeReplayRequest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let consume: Bool

    nonisolated init(schemaVersion: Int = 1, consume: Bool = true) {
        self.schemaVersion = schemaVersion
        self.consume = consume
    }

    nonisolated func asUserInfo() -> [String: Any] {
        [
            HelperExternalFileChangeUserInfoKey.schemaVersion: schemaVersion,
            HelperExternalFileChangeUserInfoKey.consume: consume,
        ]
    }

    nonisolated static func from(userInfo: [AnyHashable: Any]?) -> Self? {
        guard let userInfo else { return nil }
        guard let schemaVersion = parseInt(userInfo[HelperExternalFileChangeUserInfoKey.schemaVersion]),
              schemaVersion == 1
        else {
            return nil
        }
        guard let consume = parseBool(userInfo[HelperExternalFileChangeUserInfoKey.consume]) else {
            return nil
        }

        return Self(schemaVersion: schemaVersion, consume: consume)
    }

    private nonisolated static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private nonisolated static func parseBool(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool { return boolValue }
        if let number = value as? NSNumber { return number.boolValue }
        if let stringValue = value as? String { return Bool(stringValue) }
        return nil
    }
}

nonisolated struct HelperExternalFileChangePayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let paths: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case paths
    }

    nonisolated init(
        paths: [String],
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.paths = Self.canonicalPaths(paths)
    }

    nonisolated func merging(paths newPaths: [String], generatedAt: Date = Date()) -> Self {
        Self(
            paths: paths + newPaths,
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
        )
    }

    nonisolated func asUserInfo() -> [String: Any] {
        [
            HelperExternalFileChangeUserInfoKey.schemaVersion: schemaVersion,
            HelperExternalFileChangeUserInfoKey.generatedAt: generatedAt.timeIntervalSince1970,
            HelperExternalFileChangeUserInfoKey.paths: paths,
        ]
    }

    nonisolated static func from(userInfo: [AnyHashable: Any]?) -> Self? {
        guard let userInfo else { return nil }
        guard let schemaVersion = parseInt(userInfo[HelperExternalFileChangeUserInfoKey.schemaVersion]),
              schemaVersion == 1
        else {
            return nil
        }
        guard let paths = userInfo[HelperExternalFileChangeUserInfoKey.paths] as? [String], !paths.isEmpty else {
            return nil
        }

        let generatedAt = if let timestamp = parseDouble(userInfo[HelperExternalFileChangeUserInfoKey.generatedAt]) {
            Date(timeIntervalSince1970: timestamp)
        } else {
            Date()
        }

        return Self(paths: paths, schemaVersion: schemaVersion, generatedAt: generatedAt)
    }

    nonisolated static func canonicalPaths(_ paths: [String]) -> [String] {
        Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
    }

    private nonisolated static func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private nonisolated static func parseDouble(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double { return doubleValue }
        if let number = value as? NSNumber { return number.doubleValue }
        if let stringValue = value as? String { return Double(stringValue) }
        return nil
    }
}

actor HelperExternalFileChangeStore {
    private let fileManager: FileManager
    private let payloadURL: URL
    private let lockURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        payloadURL: URL? = nil,
        lockURL: URL? = nil,
    ) {
        self.fileManager = fileManager
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        self.payloadURL = payloadURL ?? HelperExternalFSLocation.payloadFileURL(homeDirectoryURL: homeDirectoryURL)
        self.lockURL = lockURL ?? HelperExternalFSLocation.lockFileURL(homeDirectoryURL: homeDirectoryURL)
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func replace(with payload: HelperExternalFileChangePayload) throws {
        try withExclusiveLock {
            try write(payload)
        }
    }

    func coalesce(_ newPaths: [String], generatedAt: Date = Date()) throws -> HelperExternalFileChangePayload? {
        try withExclusiveLock {
            let canonicalNewPaths = HelperExternalFileChangePayload.canonicalPaths(newPaths)
            guard !canonicalNewPaths.isEmpty else {
                return try readLocked()
            }

            let nextPayload: HelperExternalFileChangePayload = if let existing = try readLocked() {
                existing.merging(paths: canonicalNewPaths, generatedAt: generatedAt)
            } else {
                HelperExternalFileChangePayload(paths: canonicalNewPaths, generatedAt: generatedAt)
            }

            try write(nextPayload)
            return nextPayload
        }
    }

    func load() throws -> HelperExternalFileChangePayload? {
        try withExclusiveLock {
            try readLocked()
        }
    }

    func payloadForReplay(_ request: HelperExternalFileChangeReplayRequest) throws -> HelperExternalFileChangePayload? {
        try withExclusiveLock {
            let payload = try readLocked()
            guard request.consume, payload != nil else { return payload }
            try clearLocked()
            return payload
        }
    }

    func clear() throws {
        try withExclusiveLock {
            try clearLocked()
        }
    }

    private func readLocked() throws -> HelperExternalFileChangePayload? {
        guard fileManager.fileExists(atPath: payloadURL.path) else { return nil }
        let data = try Data(contentsOf: payloadURL)
        do {
            return try decoder.decode(HelperExternalFileChangePayload.self, from: data)
        } catch {
            try quarantineCorruptedPayload(data)
            return nil
        }
    }

    private func write(_ payload: HelperExternalFileChangePayload) throws {
        try ensureParentDirectoryExists()
        let data = try encoder.encode(payload)
        try data.write(to: payloadURL, options: .atomic)
    }

    private func clearLocked() throws {
        guard fileManager.fileExists(atPath: payloadURL.path) else { return }
        try fileManager.removeItem(at: payloadURL)
    }

    private func quarantineCorruptedPayload(_ data: Data) throws {
        let quarantineURL = HelperExternalFSLocation.quarantineFileURL(
            directoryURL: payloadURL.deletingLastPathComponent(),
        )
        try ensureParentDirectoryExists()
        try data.write(to: quarantineURL, options: .atomic)
        try clearLocked()
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
        guard descriptor >= 0 else {
            throw POSIXLockError.openFailed(errno)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXLockError.lockFailed(errno)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try operation()
    }
}

enum POSIXLockError: Error, Equatable {
    case openFailed(Int32)
    case lockFailed(Int32)
}

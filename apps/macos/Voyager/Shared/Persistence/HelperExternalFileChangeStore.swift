import Darwin
import Foundation

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

    static func quarantineFileURL(directoryURL: URL, generatedAt: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
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
        try withExclusiveLock { try write(payload) }
    }

    func coalesce(_ newPaths: [String], generatedAt: Date = Date()) throws -> HelperExternalFileChangePayload? {
        try withExclusiveLock {
            let canonicalNewPaths = HelperExternalFileChangePayload.canonicalPaths(newPaths)
            guard !canonicalNewPaths.isEmpty else { return try readLocked() }
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
        try withExclusiveLock { try readLocked() }
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
        try withExclusiveLock { try clearLocked() }
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
        let quarantineURL = HelperExternalFSLocation
            .quarantineFileURL(directoryURL: payloadURL.deletingLastPathComponent())
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
        guard descriptor >= 0 else { throw POSIXLockError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXLockError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

enum POSIXLockError: Error, Equatable {
    case openFailed(Int32)
    case lockFailed(Int32)
}

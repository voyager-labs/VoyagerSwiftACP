import Darwin
import Foundation

nonisolated public enum HelperExternalFSLocation {
    public static let directoryName = "Voyager"
    public static let payloadFileName = "helper_external_file_changes.json"
    public static let lockFileName = "helper_external_file_changes.lock"
    public static let quarantinePrefix = "helper_external_file_changes.corrupted"

    public static func applicationSupportRootURL(homeDirectoryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser) -> URL
    {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    public static func directoryURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        applicationSupportRootURL(homeDirectoryURL: homeDirectoryURL)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func payloadFileURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL).appendingPathComponent(payloadFileName)
    }

    public static func lockFileURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        directoryURL(homeDirectoryURL: homeDirectoryURL).appendingPathComponent(lockFileName)
    }

    public static func quarantineFileURL(directoryURL: URL, generatedAt: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent("\(quarantinePrefix)-\(timestamp).json")
    }
}

public actor HelperExternalFileChangeStore {
    private let fileManager: FileManager
    private let payloadURL: URL
    private let lockURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingPaths = Set<String>()
    private var pendingGeneratedAt: Date?

    public init(
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

    public func replace(with payload: HelperExternalFileChangePayload) throws {
        pendingPaths.removeAll()
        pendingGeneratedAt = nil
        try withExclusiveLock { try write(payload) }
    }

    public func coalesce(_ newPaths: [String], generatedAt: Date = Date()) throws -> HelperExternalFileChangePayload? {
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

    public func coalesceInMemory(_ newPaths: [String], generatedAt: Date = Date()) -> HelperExternalFileChangePayload? {
        let canonicalNewPaths = HelperExternalFileChangePayload.canonicalPaths(newPaths)
        guard !canonicalNewPaths.isEmpty else { return pendingPayload() }
        pendingPaths.formUnion(canonicalNewPaths)
        pendingGeneratedAt = generatedAt
        return pendingPayload()
    }

    public func flushPending(generatedAt: Date? = nil) throws -> HelperExternalFileChangePayload? {
        guard !pendingPaths.isEmpty else { return try load() }
        let paths = Array(pendingPaths).sorted()
        let flushDate = generatedAt ?? pendingGeneratedAt ?? Date()
        pendingPaths.removeAll()
        pendingGeneratedAt = nil

        return try withExclusiveLock {
            let nextPayload: HelperExternalFileChangePayload = if let existing = try readLocked() {
                existing.merging(paths: paths, generatedAt: flushDate)
            } else {
                HelperExternalFileChangePayload(paths: paths, generatedAt: flushDate)
            }
            try write(nextPayload)
            return nextPayload
        }
    }

    public func load() throws -> HelperExternalFileChangePayload? {
        try withExclusiveLock { try readLocked() }
    }

    public func payloadForReplay(_ request: HelperExternalFileChangeReplayRequest) throws
        -> HelperExternalFileChangePayload?
    {
        _ = try flushPending()
        return try withExclusiveLock {
            let payload = try readLocked()
            guard request.consume, payload != nil else { return payload }
            try clearLocked()
            return payload
        }
    }

    public func clear() throws {
        pendingPaths.removeAll()
        pendingGeneratedAt = nil
        try withExclusiveLock { try clearLocked() }
    }

    public func remove(_ paths: [String]) throws -> HelperExternalFileChangePayload? {
        let removedPaths = Set(HelperExternalFileChangePayload.canonicalPaths(paths))
        guard !removedPaths.isEmpty else { return try combinedPayload() }

        pendingPaths.subtract(removedPaths)
        if pendingPaths.isEmpty {
            pendingGeneratedAt = nil
        }
        let pendingPayload = pendingPayload()

        return try withExclusiveLock {
            guard let existing = try readLocked() else { return pendingPayload }

            let remainingPaths = existing.paths.filter { !removedPaths.contains($0) }
            guard !remainingPaths.isEmpty else {
                try clearLocked()
                return pendingPayload
            }

            let nextPayload = HelperExternalFileChangePayload(
                paths: remainingPaths,
                schemaVersion: existing.schemaVersion,
                generatedAt: existing.generatedAt,
            )
            try write(nextPayload)
            return mergePayload(nextPayload, with: pendingPayload)
        }
    }

    private func combinedPayload() throws -> HelperExternalFileChangePayload? {
        let pendingPayload = pendingPayload()
        return try withExclusiveLock {
            guard let existing = try readLocked() else { return pendingPayload }
            return mergePayload(existing, with: pendingPayload)
        }
    }

    private func pendingPayload() -> HelperExternalFileChangePayload? {
        guard !pendingPaths.isEmpty else { return nil }
        return HelperExternalFileChangePayload(
            paths: Array(pendingPaths).sorted(),
            generatedAt: pendingGeneratedAt ?? Date(),
        )
    }

    private func mergePayload(
        _ payload: HelperExternalFileChangePayload,
        with pendingPayload: HelperExternalFileChangePayload?,
    ) -> HelperExternalFileChangePayload {
        guard let pendingPayload else { return payload }
        return payload.merging(paths: pendingPayload.paths, generatedAt: pendingPayload.generatedAt)
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

public enum POSIXLockError: Error, Equatable {
    case openFailed(Int32)
    case lockFailed(Int32)
}

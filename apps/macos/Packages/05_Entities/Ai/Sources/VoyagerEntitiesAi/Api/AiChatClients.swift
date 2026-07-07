@preconcurrency import Darwin
@preconcurrency import Foundation

public protocol AiChatExecutionClientProtocol: Sendable {
    func execute(_ request: AiChatRequest) -> AsyncStream<AiChatEvent>
}

public protocol AiChatSessionPersistenceClientProtocol: Sendable {
    func listSessions(limit: Int?, query: String?) async throws -> [AiChatSessionSummary]
    func loadSession(id: AiChatSessionID) async throws -> AiChatSessionSnapshot?
    func saveSession(_ snapshot: AiChatSessionSnapshot) async throws
    func deleteSession(id: AiChatSessionID) async throws
}

public enum AiChatSessionPersistenceClientError: Error, Equatable, Sendable {
    case applicationSupportDirectoryUnavailable
    case corruptedRecord(AiChatSessionID)
}

public actor AiChatSessionFileStore: AiChatSessionPersistenceClientProtocol {
    public static let voyagerDirectoryName = "Voyager"
    public static let sessionsDirectoryName = "ai_chat_sessions"

    private static let lockFileName = "sessions.lock"

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let lockURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
    ) throws {
        self.fileManager = fileManager
        self.rootDirectoryURL = try rootDirectoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        lockURL = self.rootDirectoryURL.appendingPathComponent(Self.lockFileName)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    public func listSessions(limit: Int? = nil, query: String? = nil) async throws -> [AiChatSessionSummary] {
        try withExclusiveLock {
            let sessionFileURLs = try sessionFileURLs()
            let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasQuery = normalizedQuery?.isEmpty == false

            let summaries = try sessionFileURLs.compactMap { fileURL -> AiChatSessionSummary? in
                guard let snapshot = try loadSnapshotIfValid(at: fileURL) else {
                    return nil
                }
                return AiChatSessionSummary(snapshot: snapshot)
            }
            .sorted { lhs, rhs in
                if lhs.updatedAtMs == rhs.updatedAtMs {
                    return lhs.sessionID.rawValue.uuidString < rhs.sessionID.rawValue.uuidString
                }
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            .filter { summary in
                guard hasQuery, let normalizedQuery else { return true }
                return summary.matches(query: normalizedQuery)
            }

            guard let limit else { return summaries }
            return Array(summaries.prefix(max(0, limit)))
        }
    }

    public func loadSession(id: AiChatSessionID) async throws -> AiChatSessionSnapshot? {
        try withExclusiveLock {
            let fileURL = sessionFileURL(for: id)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }

            guard let snapshot = try loadSnapshotIfValid(at: fileURL) else {
                throw AiChatSessionPersistenceClientError.corruptedRecord(id)
            }
            return snapshot
        }
    }

    public func saveSession(_ snapshot: AiChatSessionSnapshot) async throws {
        try withExclusiveLock {
            let fileURL = sessionFileURL(for: snapshot.sessionID)
            if fileManager.fileExists(atPath: fileURL.path),
               let existingSnapshot = try loadSnapshotIfValid(at: fileURL),
               shouldKeepExistingSnapshot(existingSnapshot, over: snapshot)
            {
                if let mergedSnapshot = existingSnapshot.mergingIndependentMetadata(from: snapshot) {
                    let data = try encoder.encode(mergedSnapshot)
                    try replaceSessionFile(at: fileURL, with: data)
                }
                return
            }

            let data = try encoder.encode(snapshot)
            try replaceSessionFile(at: fileURL, with: data)
        }
    }

    public func deleteSession(id: AiChatSessionID) async throws {
        try withExclusiveLock {
            let fileURL = sessionFileURL(for: id)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return
            }
            try fileManager.removeItem(at: fileURL)
        }
    }
}

private extension AiChatSessionFileStore {
    static func defaultRootDirectoryURL(fileManager: FileManager) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else {
            throw AiChatSessionPersistenceClientError.applicationSupportDirectoryUnavailable
        }

        return applicationSupportURL
            .appendingPathComponent(Self.voyagerDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.sessionsDirectoryName, isDirectory: true)
    }

    func sessionFileURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        .filter(isSessionFileURL)
    }

    func sessionFileURL(for id: AiChatSessionID) -> URL {
        rootDirectoryURL.appendingPathComponent(id.rawValue.uuidString).appendingPathExtension("json")
    }

    func isSessionFileURL(_ fileURL: URL) -> Bool {
        guard fileURL.pathExtension == "json" else { return false }
        return UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) != nil
    }

    func shouldKeepExistingSnapshot(
        _ existingSnapshot: AiChatSessionSnapshot,
        over snapshot: AiChatSessionSnapshot,
    ) -> Bool {
        if existingSnapshot.updatedAtMs != snapshot.updatedAtMs {
            return existingSnapshot.updatedAtMs > snapshot.updatedAtMs
        }
        if existingSnapshot.transcriptHistory.count != snapshot.transcriptHistory.count {
            return existingSnapshot.transcriptHistory.count > snapshot.transcriptHistory.count
        }
        if existingSnapshot.lastRunID != nil, snapshot.lastRunID == nil {
            return true
        }
        if existingSnapshot.lastRequestContext != nil, snapshot.lastRequestContext == nil {
            return true
        }
        return false
    }

    func loadSnapshotIfValid(at fileURL: URL) throws -> AiChatSessionSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            try quarantineAndRemove(fileURL)
            return nil
        }

        guard !data.isEmpty else {
            try quarantineAndRemove(fileURL)
            return nil
        }

        do {
            return try decoder.decode(AiChatSessionSnapshot.self, from: data)
        } catch {
            try quarantineAndRemove(fileURL)
            return nil
        }
    }

    func quarantineAndRemove(_ fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let quarantineURL = quarantineFileURL(for: fileURL)
        try ensureRootDirectoryExists()
        try ensurePlaceholderExists(at: quarantineURL)
        _ = try fileManager.replaceItemAt(quarantineURL, withItemAt: fileURL)
        try setOwnerOnlyPermissions(quarantineURL)
    }

    func quarantineFileURL(for fileURL: URL, generatedAt: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: generatedAt).replacingOccurrences(of: ":", with: "-")
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName).corrupted-\(timestamp)")
            .appendingPathExtension("json")
    }

    func ensureRootDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func setOwnerOnlyPermissions(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path,
        )
    }

    func replaceSessionFile(at fileURL: URL, with data: Data) throws {
        try ensureRootDirectoryExists()

        let tempURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).tmp-\(UUID().uuidString)")

        try data.write(to: tempURL, options: .atomic)
        try setOwnerOnlyPermissions(tempURL)
        try ensurePlaceholderExists(at: fileURL)
        _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
        try setOwnerOnlyPermissions(fileURL)
    }

    func ensurePlaceholderExists(at fileURL: URL) throws {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }

        let didCreateFile = fileManager.createFile(
            atPath: fileURL.path,
            contents: Data(),
            attributes: [.posixPermissions: NSNumber(value: 0o600)],
        )
        guard didCreateFile else { throw CocoaError(.fileWriteUnknown) }
    }

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try ensureRootDirectoryExists()
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXLockError.openFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXLockError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

private extension AiChatSessionSnapshot {
    func mergingIndependentMetadata(from snapshot: AiChatSessionSnapshot) -> AiChatSessionSnapshot? {
        guard snapshot.sessionID == sessionID,
              snapshot.representsMetadataOnlyChange(from: self),
              snapshot.customTitle != customTitle
        else {
            return nil
        }

        return AiChatSessionSnapshot(
            sessionID: sessionID,
            status: status,
            customTitle: snapshot.customTitle,
            provider: provider,
            model: model,
            selectedModelRow: selectedModelRow,
            selectedThinking: selectedThinking,
            transcriptHistory: transcriptHistory,
            lastRequestID: lastRequestID,
            lastRunID: lastRunID,
            lastRequestContext: lastRequestContext,
            updatedAtMs: updatedAtMs,
        )
    }

    func representsMetadataOnlyChange(from existingSnapshot: AiChatSessionSnapshot) -> Bool {
        provider == existingSnapshot.provider
            && model == existingSnapshot.model
            && selectedModelRow == existingSnapshot.selectedModelRow
            && selectedThinking == existingSnapshot.selectedThinking
            && lastRequestID == existingSnapshot.lastRequestID
            && lastRunID == existingSnapshot.lastRunID
            && lastRequestContext == existingSnapshot.lastRequestContext
            && existingSnapshot.transcriptHistory.starts(with: transcriptHistory)
    }
}

private extension AiChatSessionSummary {
    func matches(query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        let searchableValues: [String?] = [
            title,
            preview,
            contextTitle,
            searchText,
            provider?.rawValue,
            model?.rawValue,
            model?.provider.rawValue,
        ]

        return searchableValues
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedQuery) }
    }
}

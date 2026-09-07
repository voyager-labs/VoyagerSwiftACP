@preconcurrency import Darwin
@preconcurrency import Foundation

public actor AIConnectionFileStore {
    private let fileManager: FileManager
    private let payloadURL: URL
    private let lockURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        payloadURL: URL,
        lockURL: URL,
        fileManager: FileManager = .default,
    ) {
        self.fileManager = fileManager
        self.payloadURL = payloadURL
        self.lockURL = lockURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public static func withDefaultHome(
        homeDirectoryURL: URL = AiConnectionRootResolver.resolveBaseRoot(),
        fileManager: FileManager = .default,
    ) -> AIConnectionFileStore {
        let payloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeDirectoryURL)
        let lockURL = AIConnectionFSLocation.lockFileURL(homeDirectoryURL: homeDirectoryURL)
        return AIConnectionFileStore(
            payloadURL: payloadURL,
            lockURL: lockURL,
            fileManager: fileManager,
        )
    }

    public static func withRepoRoot(
        repoRootURL: URL,
        fileManager: FileManager = .default,
    ) -> AIConnectionFileStore {
        AIConnectionFileStore(
            payloadURL: AIConnectionFSLocation.projectPayloadFileURL(repoRootURL: repoRootURL),
            lockURL: AIConnectionFSLocation.projectLockFileURL(repoRootURL: repoRootURL),
            fileManager: fileManager,
        )
    }

    public func migrateFromHomeIfNeeded(
        homeDirectoryURL: URL = AiConnectionRootResolver.resolveBaseRoot(),
    ) throws {
        let homePayloadURL = AIConnectionFSLocation.payloadFileURL(homeDirectoryURL: homeDirectoryURL)

        try withExclusiveLock {
            guard fileManager.fileExists(atPath: homePayloadURL.path) else { return }
            guard !fileManager.fileExists(atPath: payloadURL.path) else { return }

            try ensureParentDirectoryExists()
            let data = try Data(contentsOf: homePayloadURL)
            guard !data.isEmpty else { return }

            do {
                _ = try decoder.decode(AIConnectionsFile.self, from: data)
            } catch {
                return
            }

            try replacePayload(with: data)
        }
    }

    public func load() throws -> AIConnectionsFile {
        try withExclusiveLock {
            try loadUnlocked()
        }
    }

    public func update(
        _ transform: @Sendable (AIConnectionsFile) throws -> AIConnectionsFile,
    ) throws -> AIConnectionsFile {
        try withExclusiveLock {
            try requireSupportedSchemaUnlocked()
            let current = try loadUnlocked()
            let updated = try transform(current)
            let data = try encoder.encode(updated)
            try replacePayload(with: data)
            return updated
        }
    }

    public func write(_ file: AIConnectionsFile) throws {
        try withExclusiveLock {
            let data = try encoder.encode(file)
            try replacePayload(with: data)
        }
    }

    public func deleteCredential(for provider: AiProvider) throws {
        try withExclusiveLock {
            try requireSupportedSchemaUnlocked()
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

            guard let record = current.providers[provider.rawValue] else { return }

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

            let data = try encoder.encode(updatedFile)
            try replacePayload(with: data)
        }
    }

    private func loadUnlocked() throws -> AIConnectionsFile {
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

    /// 이 버전이 해석할 수 없는 schema의 연결 파일을 정규화 결과로 덮어 쓰지 않도록
    /// 쓰기 경계에서 지원 버전만 허용한다. 미지원 schema 파일은 디스크에 그대로 보존된다.
    private func requireSupportedSchemaUnlocked() throws {
        guard fileManager.fileExists(atPath: payloadURL.path) else { return }
        let data = try Data(contentsOf: payloadURL)
        guard !data.isEmpty else { return }
        guard let file = try? decoder.decode(AIConnectionsFile.self, from: data) else { return }
        guard file.schemaVersion == 1 else {
            throw AIConnectionFileStoreError.unsupportedSchemaVersion(file.schemaVersion)
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
            try setOwnerOnlyPermissions(quarantineURL)
            try fileManager.removeItem(at: payloadURL)
        }
    }

    private func ensureParentDirectoryExists() throws {
        let parent = payloadURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try setOwnerOnlyDirectoryPermissions(parent)
    }

    private func setOwnerOnlyDirectoryPermissions(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: url.path,
        )
    }

    private func setOwnerOnlyPermissions(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path,
        )
    }

    private func replacePayload(with data: Data) throws {
        try ensureParentDirectoryExists()

        let tempURL = payloadURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(AIConnectionFSLocation.payloadFileName).tmp-\(UUID().uuidString)")

        try data.write(to: tempURL, options: .atomic)
        try setOwnerOnlyPermissions(tempURL)
        try ensurePayloadPlaceholderExists()
        _ = try fileManager.replaceItemAt(payloadURL, withItemAt: tempURL)
        try setOwnerOnlyPermissions(payloadURL)
    }

    private func ensurePayloadPlaceholderExists() throws {
        guard !fileManager.fileExists(atPath: payloadURL.path) else { return }

        let didCreateFile = fileManager.createFile(
            atPath: payloadURL.path,
            contents: Data(),
            attributes: [.posixPermissions: NSNumber(value: 0o600)],
        )
        guard didCreateFile else { throw CocoaError(.fileWriteUnknown) }
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

public enum AIConnectionFileStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

public enum POSIXLockError: Error, Equatable {
    case openFailed(Int32)
    case lockFailed(Int32)
}

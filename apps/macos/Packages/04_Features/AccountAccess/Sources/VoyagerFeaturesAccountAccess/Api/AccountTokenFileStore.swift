@preconcurrency import Darwin
@preconcurrency import Foundation
import VoyagerEntitiesAi

// REFACTOR: 향후 VoyagerShared/CredentialStore로 AIConnectionFileStore와 통합 예정
actor AccountTokenFileStore {
    private let fileManager = FileManager.default
    private let payloadURL: URL
    private let lockURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(payloadURL: URL, lockURL: URL) {
        self.payloadURL = payloadURL
        self.lockURL = lockURL
        encoder.outputFormatting = [.sortedKeys]
    }

    static func withDefaultHome(
        homeDirectoryURL: URL = AiConnectionRootResolver.resolveBaseRoot(),
    ) -> AccountTokenFileStore {
        AccountTokenFileStore(
            payloadURL: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeDirectoryURL),
            lockURL: AccountTokenFSLocation.lockFileURL(homeDirectoryURL: homeDirectoryURL),
        )
    }

    static func withCustomHome(homeURL: URL) -> AccountTokenFileStore {
        AccountTokenFileStore(
            payloadURL: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeURL),
            lockURL: AccountTokenFSLocation.lockFileURL(homeDirectoryURL: homeURL),
        )
    }

    func read() throws -> AccountTokensFile? {
        try withExclusiveLock {
            try readUnlocked()
        }
    }

    func write(_ file: AccountTokensFile) throws {
        try withExclusiveLock {
            let data = try encoder.encode(file)
            try replacePayload(with: data)
        }
    }

    func delete() throws {
        try withExclusiveLock {
            if fileManager.fileExists(atPath: payloadURL.path) {
                try fileManager.removeItem(at: payloadURL)
            }
        }
    }

    func quarantineAndRemove() throws {
        try withExclusiveLock {
            try quarantineAndRemoveUnlocked()
        }
    }

    private func readUnlocked() throws -> AccountTokensFile? {
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: payloadURL)
        guard !data.isEmpty else {
            try quarantineAndRemoveUnlocked()
            return nil
        }

        do {
            return try decoder.decode(AccountTokensFile.self, from: data)
        } catch {
            try quarantineAndRemoveUnlocked()
            return nil
        }
    }

    private func quarantineAndRemoveUnlocked() throws {
        let quarantineURL = AccountTokenFSLocation.quarantineFileURL(
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
            .appendingPathComponent(".\(AccountTokenFSLocation.payloadFileName).tmp-\(UUID().uuidString)")

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

    /// 프로세스 간 동시 접근을 막기 위해 lock 파일에 flock(LOCK_EX)을 획득한다.
    /// .agents/rules/30-macos/06-file-backed-storage-invariants.md 준수.
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

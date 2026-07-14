@preconcurrency import Darwin
@preconcurrency import Foundation

/// ADR 001: 계정 토큰은 ~/.voyager/account_tokens.json에 저장 (home 고정).
/// AI connection 저장소(VoyagerEntitiesAi.AiConnectionRootResolver)와 root를 분리한다.
actor AccountTokenFileStore {
    private let fileManager = FileManager.default
    private let payloadURL: URL
    private let handoffStagingURL: URL
    private let lockURL: URL
    private let rollbackMarkerURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(payloadURL: URL, handoffStagingURL: URL, lockURL: URL, rollbackMarkerURL: URL) {
        self.payloadURL = payloadURL
        self.handoffStagingURL = handoffStagingURL
        self.lockURL = lockURL
        self.rollbackMarkerURL = rollbackMarkerURL
        encoder.outputFormatting = [.sortedKeys]
    }

    static func withDefaultHome(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> AccountTokenFileStore {
        AccountTokenFileStore(
            payloadURL: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeDirectoryURL),
            handoffStagingURL: AccountTokenFSLocation.handoffStagingFileURL(homeDirectoryURL: homeDirectoryURL),
            lockURL: AccountTokenFSLocation.lockFileURL(homeDirectoryURL: homeDirectoryURL),
            rollbackMarkerURL: AccountTokenFSLocation.rollbackMarkerFileURL(homeDirectoryURL: homeDirectoryURL),
        )
    }

    static func withCustomHome(homeURL: URL) -> AccountTokenFileStore {
        AccountTokenFileStore(
            payloadURL: AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeURL),
            handoffStagingURL: AccountTokenFSLocation.handoffStagingFileURL(homeDirectoryURL: homeURL),
            lockURL: AccountTokenFSLocation.lockFileURL(homeDirectoryURL: homeURL),
            rollbackMarkerURL: AccountTokenFSLocation.rollbackMarkerFileURL(homeDirectoryURL: homeURL),
        )
    }

    func read() throws -> AccountTokensFile? {
        try withExclusiveLock {
            try readUnlocked()
        }
    }

    func write(_ file: AccountTokensFile) throws {
        try withExclusiveLock {
            guard !fileManager.fileExists(atPath: rollbackMarkerURL.path) else {
                throw AccountTokenRollbackError.pendingRollback
            }
            let data = try encoder.encode(file)
            try replacePayload(with: data)
        }
    }

    func prepareHandoffWrite(_ file: AccountTokensFile) throws -> AccountTokensFile {
        try withExclusiveLock {
            if fileManager.fileExists(atPath: rollbackMarkerURL.path) {
                try removePendingHandoffUnlocked()
            } else {
                try removeHandoffStagingUnlocked()
            }

            let data = try encoder.encode(file)
            try replaceFile(at: handoffStagingURL, with: data)
            let staged = try readPayloadUnlocked(at: handoffStagingURL)
            try writeRollbackMarkerUnlocked()
            return staged
        }
    }

    func commitHandoffWrite(expectedSession: AccountSession) throws {
        try withExclusiveLock {
            guard fileManager.fileExists(atPath: rollbackMarkerURL.path) else {
                throw AccountTokenRollbackError.missingRollbackMarker
            }
            let stored = try readPayloadUnlocked(at: handoffStagingURL)
            guard stored.matches(expectedSession) else {
                throw AccountTokenRollbackError.sessionMismatch
            }
            try Task.checkCancellation()
            let data = try encoder.encode(stored)
            try replacePayload(with: data)
            try removeHandoffStagingUnlocked()
        }
    }

    func finalizeHandoffWrite() throws {
        try withExclusiveLock {
            guard fileManager.fileExists(atPath: rollbackMarkerURL.path),
                  fileManager.fileExists(atPath: payloadURL.path)
            else {
                throw AccountTokenRollbackError.missingRollbackMarker
            }
            try removeRollbackMarkerUnlocked()
        }
    }

    func delete() throws {
        try withExclusiveLock {
            if fileManager.fileExists(atPath: payloadURL.path) {
                try fileManager.removeItem(at: payloadURL)
            }
            try removeHandoffStagingUnlocked()
            if fileManager.fileExists(atPath: rollbackMarkerURL.path) {
                try fileManager.removeItem(at: rollbackMarkerURL)
            }
        }
    }

    func discard(expectedSession: AccountSession) throws {
        try withExclusiveLock {
            let hasRollbackMarker = fileManager.fileExists(atPath: rollbackMarkerURL.path)
            if fileManager.fileExists(atPath: handoffStagingURL.path) {
                let staged = try readPayloadUnlocked(at: handoffStagingURL)
                guard staged.matches(expectedSession) else { return }
                try removeCanonicalIfMatching(staged)
                try removeHandoffStagingUnlocked()
                try removeRollbackMarkerUnlocked()
                return
            }

            guard fileManager.fileExists(atPath: payloadURL.path) else {
                if hasRollbackMarker {
                    try removeRollbackMarkerUnlocked()
                }
                return
            }
            let stored = try hasRollbackMarker ? readPayloadUnlocked(at: payloadURL) : readUnlocked()
            guard let stored, stored.matches(expectedSession) else { return }

            if !hasRollbackMarker {
                try writeRollbackMarkerUnlocked()
            }
            if fileManager.fileExists(atPath: payloadURL.path) {
                try fileManager.removeItem(at: payloadURL)
            }
            try removeHandoffStagingUnlocked()
            try removeRollbackMarkerUnlocked()
        }
    }

    func quarantineAndRemove() throws {
        try withExclusiveLock {
            try quarantineAndRemoveUnlocked()
        }
    }

    private func readUnlocked() throws -> AccountTokensFile? {
        if fileManager.fileExists(atPath: rollbackMarkerURL.path) {
            return nil
        }

        guard fileManager.fileExists(atPath: payloadURL.path) else {
            return nil
        }

        do {
            return try readPayloadUnlocked(at: payloadURL)
        } catch AccountTokenRollbackError.invalidPayload {
            return nil
        }
    }

    private func readPayloadUnlocked(at url: URL) throws -> AccountTokensFile {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            if url == payloadURL {
                try quarantineAndRemoveUnlocked()
            }
            throw AccountTokenRollbackError.invalidPayload
        }

        do {
            return try decoder.decode(AccountTokensFile.self, from: data)
        } catch {
            if url == payloadURL {
                try quarantineAndRemoveUnlocked()
            }
            throw AccountTokenRollbackError.invalidPayload
        }
    }

    private func removePendingHandoffUnlocked() throws {
        if fileManager.fileExists(atPath: handoffStagingURL.path) {
            let staged = try readPayloadUnlocked(at: handoffStagingURL)
            try removeCanonicalIfMatching(staged)
            try removeHandoffStagingUnlocked()
        } else if fileManager.fileExists(atPath: payloadURL.path) {
            try fileManager.removeItem(at: payloadURL)
        }
        try removeRollbackMarkerUnlocked()
    }

    private func removeCanonicalIfMatching(_ staged: AccountTokensFile) throws {
        guard fileManager.fileExists(atPath: payloadURL.path) else { return }
        let canonical = try readPayloadUnlocked(at: payloadURL)
        if canonical.matches(staged) {
            try fileManager.removeItem(at: payloadURL)
        }
    }

    private func removeHandoffStagingUnlocked() throws {
        if fileManager.fileExists(atPath: handoffStagingURL.path) {
            try fileManager.removeItem(at: handoffStagingURL)
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

    private func writeRollbackMarkerUnlocked() throws {
        try ensureParentDirectoryExists()
        try Data("rollback-pending".utf8).write(to: rollbackMarkerURL, options: .atomic)
        try setOwnerOnlyPermissions(rollbackMarkerURL)
    }

    private func removeRollbackMarkerUnlocked() throws {
        if fileManager.fileExists(atPath: rollbackMarkerURL.path) {
            try fileManager.removeItem(at: rollbackMarkerURL)
        }
    }

    private func replacePayload(with data: Data) throws {
        try replaceFile(at: payloadURL, with: data)
    }

    private func replaceFile(at destinationURL: URL, with data: Data) throws {
        try ensureParentDirectoryExists()

        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")

        try data.write(to: tempURL, options: .atomic)
        try setOwnerOnlyPermissions(tempURL)
        try ensurePlaceholderExists(at: destinationURL)
        _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL)
        try setOwnerOnlyPermissions(destinationURL)
    }

    private func ensurePlaceholderExists(at url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }

        let didCreateFile = fileManager.createFile(
            atPath: url.path,
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

enum AccountTokenRollbackError: Error, Equatable {
    case invalidPayload
    case missingRollbackMarker
    case pendingRollback
    case sessionMismatch
}

private extension AccountTokensFile {
    func matches(_ session: AccountSession) -> Bool {
        accessToken == session.accessToken && refreshToken == session.refreshToken
    }

    func matches(_ file: AccountTokensFile) -> Bool {
        accessToken == file.accessToken && refreshToken == file.refreshToken
    }
}

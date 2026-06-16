import Foundation
import VoyagerEntitiesAi

// REFACTOR: 향후 VoyagerShared/CredentialStore로 AIConnectionFileStore와 통합 예정
public actor AccountTokenFileStore {
    private let fileManager = FileManager.default
    private let payloadURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(payloadURL: URL) {
        self.payloadURL = payloadURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public static func withDefaultHome(
        homeDirectoryURL: URL = AiConnectionRootResolver.resolveBaseRoot(),
    ) -> AccountTokenFileStore {
        let payloadURL = AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeDirectoryURL)
        return AccountTokenFileStore(payloadURL: payloadURL)
    }

    public static func withCustomHome(homeURL: URL) -> AccountTokenFileStore {
        let payloadURL = AccountTokenFSLocation.accountTokensFileURL(homeDirectoryURL: homeURL)
        return AccountTokenFileStore(payloadURL: payloadURL)
    }

    public func read() throws -> AccountTokensFile? {
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: payloadURL)
        guard !data.isEmpty else {
            try quarantineAndRemove()
            return nil
        }

        do {
            return try decoder.decode(AccountTokensFile.self, from: data)
        } catch {
            try quarantineAndRemove()
            return nil
        }
    }

    public func write(_ file: AccountTokensFile) throws {
        let data = try encoder.encode(file)
        try replacePayload(with: data)
    }

    public func delete() throws {
        if fileManager.fileExists(atPath: payloadURL.path) {
            try fileManager.removeItem(at: payloadURL)
        }
    }

    func quarantineAndRemove() throws {
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
}

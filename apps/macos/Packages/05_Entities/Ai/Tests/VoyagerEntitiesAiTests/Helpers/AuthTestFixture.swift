import Foundation

/// Creates an isolated temporary directory that mimics `~/.voyager` for auth file tests.
/// Cleans up the directory on `deinit`.
final class AuthTestFixture {
    let homeURL: URL
    let voyagerHomeURL: URL
    let authFileURL: URL

    private let originalHome: String?

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        homeURL = tmp
        voyagerHomeURL = tmp.appendingPathComponent(".voyager", isDirectory: true)
        authFileURL = voyagerHomeURL.appendingPathComponent("auth.json")

        try FileManager.default.createDirectory(
            at: voyagerHomeURL,
            withIntermediateDirectories: true
        )

        originalHome = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", tmp.path, 1)
    }

    deinit {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        }
        try? FileManager.default.removeItem(at: homeURL)
    }

    /// Writes `data` to `auth.json` with `0o600` permissions (owner read/write only).
    func writeAuthFile(_ data: Data) throws {
        try data.write(to: authFileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: authFileURL.path
        )
    }

    /// Reads the raw contents of the auth file, or throws if missing.
    func readAuthFile() throws -> Data {
        try Data(contentsOf: authFileURL)
    }

    /// Returns `true` when the auth file has `0o600` permissions.
    func authFileHasRestrictedPermissions() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: authFileURL.path
        ),
            let perms = attrs[.posixPermissions] as? UInt16
        else { return false }
        return perms == 0o600
    }
}

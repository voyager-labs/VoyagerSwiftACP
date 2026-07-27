import Foundation

/// account token 파일 I/O 테스트를 위한 격리된 임시 home 디렉토리 fixture.
/// AIConnectionFileStore 테스트의 TemporaryHomeFixture 패턴과 동일하게 동작한다.
final class TemporaryHomeFixture {
    let homeURL: URL
    let voyagerHomeURL: URL
    let accountTokensFileURL: URL

    private let originalHome: String?
    private let originalProjectRoot: String?

    init(createVoyagerDirectory: Bool = true) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        homeURL = tmp
        voyagerHomeURL = tmp.appendingPathComponent(".voyager", isDirectory: true)
        accountTokensFileURL = voyagerHomeURL.appendingPathComponent("account_tokens.json")

        if createVoyagerDirectory {
            try FileManager.default.createDirectory(
                at: voyagerHomeURL,
                withIntermediateDirectories: true,
            )
        }

        // HOME/project-root는 test-harness 격리 후 restore할 원본값으로, ProcessInfo 스냅샷이 올바르다.
        // Dotenv는 runtime config를 위한 계층이며 test fixture 복원용이 아니다.
        originalHome = ProcessInfo.processInfo.environment["HOME"]
        originalProjectRoot = ProcessInfo.processInfo.environment["VOYAGER_PROJECT_ROOT"]
        setenv("HOME", tmp.path, 1)
        setenv("VOYAGER_PROJECT_ROOT", tmp.path, 1)
    }

    deinit {
        restoreEnvironmentVariable("HOME", originalValue: originalHome)
        restoreEnvironmentVariable("VOYAGER_PROJECT_ROOT", originalValue: originalProjectRoot)
        try? FileManager.default.removeItem(at: homeURL)
    }

    struct FileSnapshot: Equatable {
        let exists: Bool
        let contents: Data?
        let permissions: NSNumber?
    }

    func snapshotFile(at url: URL) -> FileSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return FileSnapshot(exists: false, contents: nil, permissions: nil)
        }

        let contents = try? Data(contentsOf: url)
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let permissions = attributes?[.posixPermissions] as? NSNumber
        return FileSnapshot(exists: true, contents: contents, permissions: permissions)
    }

    private func restoreEnvironmentVariable(_ name: String, originalValue: String?) {
        if let originalValue {
            setenv(name, originalValue, 1)
        } else {
            unsetenv(name)
        }
    }
}

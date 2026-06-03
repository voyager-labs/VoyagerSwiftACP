import Foundation

/// Creates an isolated temporary home directory for filesystem-backed AI tests.
final class TemporaryHomeFixture {
    let realHomeURL: URL
    let homeURL: URL
    let voyagerHomeURL: URL
    let authFileURL: URL

    private let originalHome: String?
    private let originalProjectRoot: String?

    init(createVoyagerDirectory: Bool = true) throws {
        realHomeURL = FileManager.default.homeDirectoryForCurrentUser

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        homeURL = tmp
        voyagerHomeURL = tmp.appendingPathComponent(".voyager", isDirectory: true)
        authFileURL = voyagerHomeURL.appendingPathComponent("auth.json")

        if createVoyagerDirectory {
            try FileManager.default.createDirectory(
                at: voyagerHomeURL,
                withIntermediateDirectories: true
            )
        }

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

    var realAuthFileURL: URL {
        realHomeURL.appendingPathComponent(".voyager/auth.json")
    }

    struct FileSnapshot: Equatable {
        let exists: Bool
        let contents: Data?
        let modificationDate: Date?
    }

    func snapshotRealAuthFile() -> FileSnapshot {
        snapshotFile(at: realAuthFileURL)
    }

    func snapshotFile(at url: URL) -> FileSnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return FileSnapshot(exists: false, contents: nil, modificationDate: nil)
        }

        let contents = try? Data(contentsOf: url)
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        return FileSnapshot(exists: true, contents: contents, modificationDate: modificationDate)
    }

    private func restoreEnvironmentVariable(_ name: String, originalValue: String?) {
        if let originalValue {
            setenv(name, originalValue, 1)
        } else {
            unsetenv(name)
        }
    }
}

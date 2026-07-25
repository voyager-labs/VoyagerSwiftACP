import Foundation

/// Copies repo fixtures into an isolated temporary sandbox for File Manager reducer tests.
///
/// The source fixture remains under `fixtures/fixtures/**`; tests use copied files so reducer
/// inputs are real filesystem paths without mutating the shared fixture source.
struct FileManagerFixtureSandbox {
    let root: URL
    let originalFixture: URL
    let fileURL: URL
    let symlinkedFileURL: URL

    /// Copies a single fixture into a temp sandbox and creates a sibling symlink to its directory.
    ///
    /// This supports path-normalization tests where two distinct existing path strings should
    /// resolve to the same file via filesystem symlinks.
    static func copyingFileWithDirectorySymlink(from repoRelativePath: String) throws -> FileManagerFixtureSandbox {
        let repoRoot = try resolveRepoRoot()
        let original = repoRoot.appendingPathComponent(repoRelativePath)

        guard FileManager.default.fileExists(atPath: original.path) else {
            throw FileManagerFixtureSandboxError.fixtureNotFound(
                path: original.path,
                repoRelative: repoRelativePath,
            )
        }

        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerFileManagerFixtureSandbox-\(UUID().uuidString)", isDirectory: true)
        let realDirectory = sandboxRoot.appendingPathComponent("real", isDirectory: true)
        let symlinkDirectory = sandboxRoot.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)

        let copiedFile = realDirectory.appendingPathComponent(original.lastPathComponent)
        try FileManager.default.copyItem(at: original, to: copiedFile)
        try FileManager.default.createSymbolicLink(at: symlinkDirectory, withDestinationURL: realDirectory)

        assert(
            FileManager.default.fileExists(atPath: original.path),
            "Original fixture must remain intact after copy: \(original.path)",
        )
        assert(
            FileManager.default.fileExists(atPath: copiedFile.path),
            "Copied fixture must exist for reducer input: \(copiedFile.path)",
        )

        return FileManagerFixtureSandbox(
            root: sandboxRoot,
            originalFixture: original,
            fileURL: copiedFile,
            symlinkedFileURL: symlinkDirectory.appendingPathComponent(original.lastPathComponent),
        )
    }

    /// 읽기 전용 reducer 입력에 사용할 실제 fixture 디렉토리를 반환한다.
    static func readOnlyDirectory(from repoRelativePath: String) throws -> URL {
        let original = try resolveRepoRoot().appendingPathComponent(repoRelativePath)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw FileManagerFixtureSandboxError.fixtureNotFound(
                path: original.path,
                repoRelative: repoRelativePath,
            )
        }

        return original
    }

    /// Removes only the temporary sandbox root. Original fixtures are never touched.
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Private

    private static func resolveRepoRoot() throws -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)

        for _ in 0 ..< 12 {
            let fixturesDir = url.appendingPathComponent("fixtures/fixtures", isDirectory: true)
            if FileManager.default.fileExists(atPath: fixturesDir.path) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }

        throw FileManagerFixtureSandboxError.repoRootNotFound(searchFrom: cwd)
    }
}

enum FileManagerFixtureSandboxError: Error, CustomStringConvertible {
    case fixtureNotFound(path: String, repoRelative: String)
    case repoRootNotFound(searchFrom: String)

    var description: String {
        switch self {
        case let .fixtureNotFound(path, repoRelative):
            "Fixture not found at '\(path)' (repo-relative: '\(repoRelative)'). "
                + "Run 'git submodule update --init --recursive'."
        case let .repoRootNotFound(searchFrom):
            "Could not resolve repo root searching from '\(searchFrom)'. "
                + "Ensure tests run from within the voyager-app repo."
        }
    }
}

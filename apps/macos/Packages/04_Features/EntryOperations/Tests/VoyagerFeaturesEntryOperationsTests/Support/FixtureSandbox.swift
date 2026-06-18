import Foundation

/// Copies fixture files into an isolated temporary sandbox for mutation tests.
///
/// Resolves repo-relative fixture paths (e.g. `fixtures/fixtures/images/jpeg/hopper.jpg`)
/// by walking up from the test executable's working directory to find the repo root.
struct FixtureSandbox {
    let root: URL
    let originalFixture: URL

    var fileURL: URL {
        root.appendingPathComponent(originalFixture.lastPathComponent)
    }

    /// Copies a single file from the repo-relative path into a temp sandbox.
    /// - Parameter repoRelativePath: e.g. `fixtures/fixtures/images/jpeg/hopper.jpg`
    static func copyingFile(from repoRelativePath: String) throws -> FixtureSandbox {
        try copying(from: repoRelativePath)
    }

    /// Copies a directory tree from the repo-relative path into a temp sandbox.
    /// - Parameter repoRelativePath: e.g. `fixtures/fixtures/documents`
    static func copyingDirectory(from repoRelativePath: String) throws -> FixtureSandbox {
        try copying(from: repoRelativePath)
    }

    /// Removes only the temp sandbox root. Original fixtures are never touched.
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Private

    private static func copying(from repoRelativePath: String) throws -> FixtureSandbox {
        let repoRoot = try resolveRepoRoot()
        let original = repoRoot.appendingPathComponent(repoRelativePath)

        guard FileManager.default.fileExists(atPath: original.path) else {
            throw FixtureSandboxError.fixtureNotFound(
                path: original.path,
                repoRelative: repoRelativePath,
            )
        }

        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerFixtureSandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)

        let destination = sandboxRoot.appendingPathComponent(original.lastPathComponent)
        try FileManager.default.copyItem(at: original, to: destination)

        assert(
            FileManager.default.fileExists(atPath: original.path),
            "Original fixture must remain intact after copy: \(original.path)",
        )

        return FixtureSandbox(root: sandboxRoot, originalFixture: original)
    }

    /// Walk up from CWD to find the repo root (directory containing `.git` or `Package.swift` at repo level).
    private static func resolveRepoRoot() throws -> URL {
        let cwd = FileManager.default.currentDirectoryPath
        var url = URL(fileURLWithPath: cwd)

        for _ in 0 ..< 10 {
            let gitDir = url.appendingPathComponent(".git")
            let rootManifest = url.appendingPathComponent("Package.swift")

            if FileManager.default.fileExists(atPath: gitDir.path) ||
                FileManager.default.fileExists(atPath: rootManifest.path)
            {
                // Verify fixtures exist under this candidate root
                let fixturesDir = url.appendingPathComponent("fixtures/fixtures")
                if FileManager.default.fileExists(atPath: fixturesDir.path) {
                    return url
                }
            }

            guard let parent = url.pathComponents.count > 1 ? url.deletingLastPathComponent() : nil else {
                break
            }
            url = parent
        }

        throw FixtureSandboxError.repoRootNotFound(searchFrom: cwd)
    }
}

enum FixtureSandboxError: Error, CustomStringConvertible {
    case fixtureNotFound(path: String, repoRelative: String)
    case repoRootNotFound(searchFrom: String)

    var description: String {
        switch self {
        case let .fixtureNotFound(path, repoRelative):
            "Fixture not found at '\(path)' (repo-relative: '\(repoRelative)')."
                + " Run 'git submodule update --init --recursive'."
        case let .repoRootNotFound(searchFrom):
            "Could not resolve repo root searching from '\(searchFrom)'."
                + " Ensure tests run from within the voyager-app repo."
        }
    }
}

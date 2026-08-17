import Foundation

struct EntryMutationFixtureSandbox {
    let root: URL
    let originalFixture: URL

    var fileURL: URL {
        root.appendingPathComponent(originalFixture.lastPathComponent)
    }

    static func copyingFile(from repoRelativePath: String) throws -> Self {
        let repoRoot = try resolveRepoRoot()
        let originalFixture = repoRoot.appendingPathComponent(repoRelativePath)
        guard FileManager.default.fileExists(atPath: originalFixture.path) else {
            throw EntryMutationFixtureSandboxError.fixtureNotFound(originalFixture.path)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerEntryMutationFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: originalFixture,
            to: root.appendingPathComponent(originalFixture.lastPathComponent),
        )
        return Self(root: root, originalFixture: originalFixture)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func resolveRepoRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 12 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("fixtures/fixtures").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw EntryMutationFixtureSandboxError.repoRootNotFound
    }
}

enum EntryMutationFixtureSandboxError: Error {
    case fixtureNotFound(String)
    case repoRootNotFound
}

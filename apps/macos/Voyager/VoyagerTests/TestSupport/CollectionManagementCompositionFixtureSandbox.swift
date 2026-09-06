import Foundation

struct CollectionManagementCompositionFixtureSandbox {
    let root: URL
    let originalFixture: URL
    let collectionURL: URL
    let searchRoot: URL

    static func make() throws -> Self {
        let repoRoot = try resolveRepoRoot()
        let originalFixture = repoRoot.appendingPathComponent(
            "fixtures/fixtures/collections/empty_definition_collection.voycoll",
            isDirectory: true,
        )
        guard FileManager.default.fileExists(atPath: originalFixture.path) else {
            throw CollectionManagementCompositionFixtureSandboxError.fixtureNotFound(originalFixture.path)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerCollectionManagementComposition-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let collectionURL = root.appendingPathComponent(originalFixture.lastPathComponent, isDirectory: true)
        let searchRoot = root.appendingPathComponent("SearchRoot", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: originalFixture, to: collectionURL)
        try FileManager.default.createDirectory(at: searchRoot, withIntermediateDirectories: true)

        return Self(
            root: root,
            originalFixture: originalFixture,
            collectionURL: collectionURL,
            searchRoot: searchRoot,
        )
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
        throw CollectionManagementCompositionFixtureSandboxError.repoRootNotFound
    }
}

enum CollectionManagementCompositionFixtureSandboxError: Error {
    case fixtureNotFound(String)
    case repoRootNotFound
}

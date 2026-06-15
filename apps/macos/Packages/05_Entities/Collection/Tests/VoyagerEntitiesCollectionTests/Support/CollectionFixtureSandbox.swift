import Foundation

struct CollectionFixtureSandbox {
    let root: URL
    let originalFixture: URL
    let fileURL: URL

    static func copyingFile(from relativeFixturePath: String) throws -> CollectionFixtureSandbox {
        try copyFixture(from: relativeFixturePath, isDirectory: false)
    }

    static func copyingDirectory(from relativeFixturePath: String) throws -> CollectionFixtureSandbox {
        try copyFixture(from: relativeFixturePath, isDirectory: true)
    }

    func cleanup() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private static func copyFixture(
        from relativeFixturePath: String,
        isDirectory: Bool,
    ) throws -> CollectionFixtureSandbox {
        let repoRoot = try findRepoRoot()
        let originalFixture = repoRoot.appendingPathComponent(relativeFixturePath)
        var isDirectoryValue: ObjCBool = false
        guard FileManager.default.fileExists(atPath: originalFixture.path, isDirectory: &isDirectoryValue) else {
            throw CollectionFixtureSandboxError.fixtureNotFound(relativeFixturePath)
        }
        guard isDirectoryValue.boolValue == isDirectory else {
            throw CollectionFixtureSandboxError.fixtureTypeMismatch(
                path: relativeFixturePath,
                expectedDirectory: isDirectory,
            )
        }

        let sandboxRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerCollectionFixtureSandbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: sandboxRoot,
            withIntermediateDirectories: true,
        )

        let copiedFixture = sandboxRoot.appendingPathComponent(originalFixture.lastPathComponent)
        try FileManager.default.copyItem(at: originalFixture, to: copiedFixture)

        guard FileManager.default.fileExists(atPath: originalFixture.path) else {
            // 원본 fixture는 테스트 입력의 기준점이므로 sandbox 작업 중 사라지면 안 된다.
            throw CollectionFixtureSandboxError.originalFixtureMutated(relativeFixturePath)
        }

        return CollectionFixtureSandbox(
            root: sandboxRoot,
            originalFixture: originalFixture,
            fileURL: copiedFixture,
        )
    }

    private static func findRepoRoot() throws -> URL {
        var currentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let gitDirectory = currentURL.appendingPathComponent(".git")
            let rootPackage = currentURL.appendingPathComponent("Package.swift")
            let fixturesRoot = currentURL.appendingPathComponent("fixtures/fixtures")
            if FileManager.default.fileExists(atPath: gitDirectory.path)
                || (FileManager.default.fileExists(atPath: rootPackage.path)
                    && FileManager.default.fileExists(atPath: fixturesRoot.path))
            {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                throw CollectionFixtureSandboxError.repoRootNotFound
            }
            currentURL = parentURL
        }
    }
}

enum CollectionFixtureSandboxError: Error, CustomStringConvertible {
    case repoRootNotFound
    case fixtureNotFound(String)
    case fixtureTypeMismatch(path: String, expectedDirectory: Bool)
    case originalFixtureMutated(String)

    var description: String {
        switch self {
        case .repoRootNotFound:
            return "Repository root containing fixtures/fixtures was not found. Run tests from the repository or package checkout."
        case let .fixtureNotFound(path):
            return "Fixture not found at \(path). Ensure the fixtures submodule is initialized."
        case let .fixtureTypeMismatch(path, expectedDirectory):
            let expectedType = expectedDirectory ? "directory" : "file"
            return "Fixture at \(path) is not a \(expectedType)."
        case let .originalFixtureMutated(path):
            return "Original fixture at \(path) was unexpectedly mutated or removed."
        }
    }
}

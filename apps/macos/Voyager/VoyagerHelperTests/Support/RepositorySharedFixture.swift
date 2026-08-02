import Foundation

enum RepositorySharedFixture {
    static func decode<T: Decodable>(
        fileName: String,
        sourceFilePath: String,
    ) throws -> T {
        let fileURL = try resolve(fileName: fileName, sourceFilePath: sourceFilePath)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func resolve(fileName: String, sourceFilePath: String) throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()

        while true {
            let repositoryMarker = directory.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: repositoryMarker.path) {
                let sharedDirectory = directory.appendingPathComponent("shared", isDirectory: true)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: sharedDirectory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else {
                    throw RepositorySharedFixtureError.sharedDirectoryMissing(repositoryRoot: directory.path)
                }

                let fixtureURL = sharedDirectory.appendingPathComponent(fileName)
                var fixtureIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: fixtureURL.path, isDirectory: &fixtureIsDirectory),
                      !fixtureIsDirectory.boolValue
                else {
                    throw RepositorySharedFixtureError.fixtureMissing(path: fixtureURL.path)
                }
                return fixtureURL
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                throw RepositorySharedFixtureError.repositoryRootMissing(sourceFilePath: sourceFilePath)
            }
            directory = parent
        }
    }
}

private enum RepositorySharedFixtureError: LocalizedError {
    case repositoryRootMissing(sourceFilePath: String)
    case sharedDirectoryMissing(repositoryRoot: String)
    case fixtureMissing(path: String)

    var errorDescription: String? {
        switch self {
        case let .repositoryRootMissing(sourceFilePath):
            "Repository root containing .git was not found from source file: \(sourceFilePath)"
        case let .sharedDirectoryMissing(repositoryRoot):
            "Repository shared fixture directory is missing at: \(repositoryRoot)/shared"
        case let .fixtureMissing(path):
            "Repository shared fixture is missing at: \(path)"
        }
    }
}

import VoyagerEntitiesEntry
@testable import VoyagerFeaturesEntryOperations
import XCTest

final class EntryClientFileOpsTests: XCTestCase {
    func testCreateFolderInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let folderName = "New Folder"
        try await EntryFileOpsClient.liveValue.createFolder(tempDirectory.url, folderName)

        let folderURL = tempDirectory.url.appendingPathComponent(folderName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
    }

    func testMoveFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let sourceURL = try makeFile(in: tempDirectory.url, name: "source.txt")
        let destinationURL = tempDirectory.url.appendingPathComponent("destination.txt")

        try await EntryFileOpsClient.liveValue.moveFile(sourceURL, destinationURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testRenameFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let sourceURL = try makeFile(in: tempDirectory.url, name: "old.txt")
        let destinationURL = tempDirectory.url.appendingPathComponent("new.txt")

        try await EntryFileOpsClient.liveValue.renameFile(sourceURL, destinationURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    func testDeleteFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let fileURL = try makeFile(in: tempDirectory.url, name: "delete.txt")

        try await EntryFileOpsClient.liveValue.deleteImmediately(fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMakeTagsForPersistence_PreservesExistingColorCode() {
        let tags = EntryFileOpsTagPersistenceResolver.makeTags(
            tagNames: ["Work"],
            existingTags: [Tag(name: "Work", colorCode: 4)],
            favoriteTags: [Tag(name: "Work", colorCode: 6)],
        )

        XCTAssertEqual(tags, [Tag(name: "Work", colorCode: 4)])
    }

    func testMakeTagsForPersistence_UsesFavoriteTagColorForNewTag() {
        let tags = EntryFileOpsTagPersistenceResolver.makeTags(
            tagNames: ["Urgent"],
            existingTags: [],
            favoriteTags: [Tag(name: "Urgent", colorCode: 6)],
        )

        XCTAssertEqual(tags, [Tag(name: "Urgent", colorCode: 6)])
    }

    func testMakeTagsForPersistence_FallsBackToNeutralColorWhenFavoriteTagIsMissing() {
        let tags = EntryFileOpsTagPersistenceResolver.makeTags(
            tagNames: ["Adhoc"],
            existingTags: [],
            favoriteTags: [],
        )

        XCTAssertEqual(tags, [Tag(name: "Adhoc", colorCode: 0)])
    }
}

private struct TempDirectory {
    let url: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        url = baseURL
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private func makeFile(in directory: URL, name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let data = Data("test".utf8)
    try data.write(to: url)
    return url
}

import VoyagerEntitiesEntry
import VoyagerEntitiesTag
@testable import VoyagerFeaturesEntryOperations
import XCTest

final class EntryClientFileOpsTests: XCTestCase {
    /// 임시 디렉터리 안에서 폴더 생성이 실제 파일 시스템에 반영되는지 검증
    func testCreateFolderInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let folderName = "New Folder"
        try await EntryFileOpsClient.liveValue.createFolder(tempDirectory.url, folderName)

        let folderURL = tempDirectory.url.appendingPathComponent(folderName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
    }

    /// 파일 이동이 source 삭제와 destination 생성으로 정확히 이어지는지 검증
    func testMoveFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let sourceURL = try makeFile(in: tempDirectory.url, name: "source.txt")
        let destinationURL = tempDirectory.url.appendingPathComponent("destination.txt")

        try await EntryFileOpsClient.liveValue.moveFile(sourceURL, destinationURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    /// 파일 이름 변경이 기존 파일을 새 경로로 옮기는지 검증
    func testRenameFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let sourceURL = try makeFile(in: tempDirectory.url, name: "old.txt")
        let destinationURL = tempDirectory.url.appendingPathComponent("new.txt")

        try await EntryFileOpsClient.liveValue.renameFile(sourceURL, destinationURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
    }

    /// 즉시 삭제가 파일 시스템에서 실제 파일을 제거하는지 검증
    func testDeleteFileInTemporaryDirectory() async throws {
        let tempDirectory = try TempDirectory()
        defer { tempDirectory.cleanup() }

        let fileURL = try makeFile(in: tempDirectory.url, name: "delete.txt")

        try await EntryFileOpsClient.liveValue.deleteImmediately(fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// 기존 태그가 있으면 색상 코드를 그대로 보존하는지 검증
    func testMakeTagsForPersistence_PreservesExistingColorCode() {
        let tags = EntryFileOpsTagPersistenceResolver.makeTags(
            tagNames: ["Work"],
            existingTags: [Tag(name: "Work", colorCode: 4)],
            favoriteTags: [Tag(name: "Work", colorCode: 6)],
        )

        XCTAssertEqual(tags, [Tag(name: "Work", colorCode: 4)])
    }

    /// 즐겨찾기 태그 색상을 새 태그의 기본 색상으로 사용하는지 검증
    func testMakeTagsForPersistence_UsesFavoriteTagColorForNewTag() {
        let tags = EntryFileOpsTagPersistenceResolver.makeTags(
            tagNames: ["Urgent"],
            existingTags: [],
            favoriteTags: [Tag(name: "Urgent", colorCode: 6)],
        )

        XCTAssertEqual(tags, [Tag(name: "Urgent", colorCode: 6)])
    }

    /// 즐겨찾기 태그가 없을 때 중립 색상으로 폴백하는지 검증
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

import Foundation
@testable import VoyagerEntitiesTag
import XCTest

@MainActor
final class EOP004EditEntryTagsMetadataTests: XCTestCase {
    // MARK: - EOP-004-edit_entry_tags

    /// EOP-004-edit_entry_tags: Tag metadata loading reports no tags for untagged files.
    /// Entry tag editing depends on a stable metadata boundary for files that do not yet have Finder tags.
    /// - 검증 내용: TagMetadataClient.loadTags nil behavior for untagged files
    /// - 사전 조건: A temporary file exists without tag metadata
    /// - 기대 결과: Tag metadata loading returns nil rather than an empty phantom tag list
    func testLoadTagsNoTagsReturnsNil() throws {
        let tempDir = try makeTemporaryDirectory()
        let testFile = tempDir.appendingPathComponent("untagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = TagMetadataClient.loadTags(from: testFile)

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: Tag metadata round-trips Finder tag color codes.
    /// Editing entry tags must preserve the stored Finder tag label/color payload.
    /// - 검증 내용: TagMetadataClient.setTags and loadTags color-code preservation
    /// - 사전 조건: A temporary file is assigned a color-coded tag through TagMetadataClient
    /// - 기대 결과: Loading the file tags returns the same tag name and color code
    func testSetTagsThenLoadTagsPreservesColorCode() throws {
        let tempDir = try makeTemporaryDirectory()
        let testFile = tempDir.appendingPathComponent("tagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try TagMetadataClient.setTags([Tag(name: "TestTag", colorCode: 6)], for: testFile)
        } catch {
            throw XCTSkip("이 환경에서는 확장 속성을 설정할 수 없습니다: \(error)")
        }

        let loadedTags = TagMetadataClient.loadTags(from: testFile)

        XCTAssertEqual(loadedTags, [Tag(name: "TestTag", colorCode: 6)])
    }

    /// EOP-004-edit_entry_tags: Tag metadata loading reports no tags for missing files.
    /// Entry tag editing must treat missing file metadata as unavailable rather than fabricated tags.
    /// - 검증 내용: TagMetadataClient.loadTags missing-file fallback
    /// - 사전 조건: The queried file URL does not exist
    /// - 기대 결과: Loading tag metadata returns nil
    func testLoadTagsNonExistentFileReturnsNil() {
        let nonExistent = URL(fileURLWithPath: "/non/existent/path/file.txt")

        let result = TagMetadataClient.loadTags(from: nonExistent)

        XCTAssertNil(result)
    }

    /// EOP-004-edit_entry_tags: Tag name metadata can be stored and reloaded through the public tag-name boundary.
    /// Entry tag editing uses tag names as the stable user-visible label surface.
    /// - 검증 내용: TagMetadataClient.setTagNames and loadTagNames round-trip behavior
    /// - 사전 조건: A temporary file is assigned two tag names
    /// - 기대 결과: Loading tag names returns the stored names without dropping either label
    func testSetTagNamesThenLoadTagNamesReturnsNames() throws {
        let tempDir = try makeTemporaryDirectory()
        let testFile = tempDir.appendingPathComponent("tag-names-file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try TagMetadataClient.setTagNames(["Red", "Green"], for: testFile)
        } catch {
            throw XCTSkip("이 환경에서는 확장 속성을 설정할 수 없습니다: \(error)")
        }

        let tagNames = try TagMetadataClient.loadTagNames(from: testFile)

        XCTAssertEqual(Set(tagNames), Set(["Red", "Green"]))
    }

    /// EOP-004-edit_entry_tags: Removing tag names clears the stored tag metadata.
    /// Entry tag editing must be able to represent a file returning to the no-tag state.
    /// - 검증 내용: TagMetadataClient.setTagNames empty removal behavior
    /// - 사전 조건: A temporary file first receives one tag and is then saved with an empty tag-name list
    /// - 기대 결과: Loading tag metadata returns nil after removal
    func testSetTagNamesEmptyRemovesStoredTags() throws {
        let tempDir = try makeTemporaryDirectory()
        let testFile = tempDir.appendingPathComponent("cleared-tags-file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try TagMetadataClient.setTags([Tag(name: "Red", colorCode: 1)], for: testFile)
            try TagMetadataClient.setTagNames([], for: testFile)
        } catch {
            throw XCTSkip("이 환경에서는 확장 속성을 설정할 수 없습니다: \(error)")
        }

        XCTAssertNil(TagMetadataClient.loadTags(from: testFile))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}

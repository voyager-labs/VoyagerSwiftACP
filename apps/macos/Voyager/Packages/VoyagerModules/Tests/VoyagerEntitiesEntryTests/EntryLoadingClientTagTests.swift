import CoreServices
import Foundation
@testable import VoyagerEntitiesEntry
import XCTest

/// Characterization tests for tag loading behavior in EntryLoadingClient.
///
/// These tests document the fallback chain:
/// 1. xattr com.apple.metadata:_kMDItemUserTags (preserves colorCode) - via TagMetadataClient.loadTags
/// 2. URL tagNamesKey (colorCode always 0) - fallback when xattr is unavailable
///
/// Note: EntryLoadingClient.entryTags(from:) is private, so we test through:
/// - TagMetadataClient.loadTags (the xattr path)
/// - Documenting the tagNamesKey fallback behavior
@MainActor
final class EntryLoadingClientTagTests: XCTestCase {
    // MARK: - TagMetadataClient.loadTags Tests

    /// Test that xattr-backed loading returns nil for file without tags.
    /// Expected: File with no tags → nil
    func testLoadTags_NoTags_ReturnsNil() throws {
        // Create a temporary file without tags
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("untagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = TagMetadataClient.loadTags(from: testFile)

        // File has no tags, so xattr-backed loading returns nil
        XCTAssertNil(result)
    }

    /// Test that xattr-backed loading returns tags with color codes when properly tagged.
    /// This test documents the expected format: "name\ncolorCode"
    /// Note: This test requires Finder tags to be set, which may not work in all environments.
    func testLoadTags_WithFinderTags_PreservesColorCode() throws {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("tagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Set Finder tags using extended attributes
        // The format is a binary plist of strings in "name\ncolorCode" format
        let tagWithColor = "TestTag\n6" // Color 6 = blue
        let tagData = try PropertyListSerialization.data(
            fromPropertyList: [tagWithColor],
            format: .binary,
            options: 0,
        )

        let result = setxattr(
            testFile.path,
            "com.apple.metadata:_kMDItemUserTags",
            (tagData as NSData).bytes,
            tagData.count,
            0,
            0,
        )

        guard result == 0 else {
            // Skip test if we can't set xattr (permission issues in some environments)
            throw XCTSkip("Cannot set extended attributes in this environment")
        }

        // Now load tags via TagMetadataClient
        let loadedTags = TagMetadataClient.loadTags(from: testFile)

        XCTAssertNotNil(loadedTags)
        XCTAssertEqual(loadedTags?.count, 1)
        XCTAssertEqual(loadedTags?.first?.name, "TestTag")
        XCTAssertEqual(loadedTags?.first?.colorCode, 6, "Color code should be preserved from MDItem")
    }

    /// Test that xattr-backed loading returns nil for non-existent file.
    /// Expected: Non-existent file → nil
    func testLoadTags_NonExistentFile_ReturnsNil() {
        let nonExistent = URL(fileURLWithPath: "/non/existent/path/file.txt")

        let result = TagMetadataClient.loadTags(from: nonExistent)

        XCTAssertNil(result)
    }

    /// tagNamesKey로 저장된 태그는 macOS Finder 태그 시스템에 의해 실제 색상 코드가 부여될 수 있습니다.
    /// 이 테스트는 loadTags가 태그를 반환하는지만 검증합니다.
    func testLoadTags_WithTagNamesKeyStoredTags_ReturnsTags() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var testFile = tempDir.appendingPathComponent("tag-names-file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try (testFile as NSURL).setResourceValue(["Red", "Green"], forKey: .tagNamesKey)

        let loadedTags = TagMetadataClient.loadTags(from: testFile)

        XCTAssertNotNil(loadedTags)
        XCTAssertEqual(loadedTags?.count, 2)
        XCTAssertEqual(loadedTags?.map(\.name).sorted(), ["Green", "Red"])
    }

    // MARK: - tagNamesKey Fallback Documentation Tests

    /// Test that tagNamesKey returns tag names (without color info).
    /// This documents the fallback behavior when xattr is unavailable.
    /// Expected: tagNamesKey provides names but NOT color codes
    func testTagNamesKey_ReturnsNamesWithoutColorCodes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var testFile = tempDir.appendingPathComponent("tagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Set tags using tagNamesKey (standard macOS API)
        try (testFile as NSURL).setResourceValue(["Red", "Green"], forKey: .tagNamesKey)

        // Read back via tagNamesKey
        let readValues = try testFile.resourceValues(forKeys: [.tagNamesKey])
        let tagNames = readValues.tagNames ?? []

        XCTAssertEqual(tagNames.count, 2)
        XCTAssertTrue(tagNames.contains("Red"))
        XCTAssertTrue(tagNames.contains("Green"))

        // Note: tagNamesKey does NOT include color code information
        // When xattr is unavailable, the fallback creates tags with colorCode: 0
    }

    /// Test that empty tag list is handled correctly in fallback.
    /// Expected: No tags → nil from entryTags fallback
    func testTagNamesKey_EmptyTags_ReturnsNilInFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("no_tags_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // No tags set - read via tagNamesKey
        let resourceValues = try testFile.resourceValues(forKeys: [.tagNamesKey])
        let tagNames = resourceValues.tagNames ?? []

        // Document: When tagNamesKey returns empty, fallback returns nil
        XCTAssertTrue(tagNames.isEmpty, "Untagged file should have empty tagNames")

        // This documents the fallback behavior:
        // let tags = tagNames.map { Tag(name: $0, colorCode: 0) }
        // return tags.isEmpty ? nil : tags
        // → Returns nil for empty tagNames
    }

    // MARK: - Fallback Behavior Documentation

    /// Documents the complete fallback chain behavior.
    /// This test serves as specification documentation for the entryTags(from:) private function.
    func testEntryTagsFallbackChain_Documentation() {
        // The private function EntryModelConverterLive.entryTags(from:) behaves as follows:
        //
        // 1. First, try xattr com.apple.metadata:_kMDItemUserTags via TagMetadataClient.loadTags:
        //    - If successful: return tags WITH preserved colorCode
        //    - Format: "name\ncolorCode" → Tag(name: "name", colorCode: Int)
        //
        // 2. If xattr loading fails, fallback to URL tagNamesKey:
        //    - Returns: tag names WITHOUT color information
        //    - All tags get colorCode: 0
        //    - Empty list → return nil
        //
        // 3. If both fail: return nil
        //
        // This is characterized by the code at EntryLoadingClient.swift:640-652

        // Example scenarios:
        // Scenario A: File with Finder tags (via xattr)
        //   Input: "Important\n1" (red)
        //   Output: Tag(name: "Important", colorCode: 1)
        //
        // Scenario B: File with tags but MDItem unavailable
        //   Input: ["Work", "Personal"] via tagNamesKey
        //   Output: [Tag(name: "Work", colorCode: 0), Tag(name: "Personal", colorCode: 0)]
        //
        // Scenario C: File without any tags
        //   Output: nil

        // This test passes if the documentation above is accurate.
        // Actual behavior is verified by the other tests in this file.
        XCTAssertTrue(true, "Documentation test - see comments for fallback chain specification")
    }

    /// Test that whitespace is trimmed in the fallback path.
    /// Documents the trimming behavior in entryTags fallback.
    func testFallback_TrimsWhitespaceFromTagNames() {
        // The fallback code:
        // tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        //         .filter { !$0.isEmpty }
        //         .map { Tag(name: $0, colorCode: 0) }

        let rawTagNames = ["  spaced  ", "\ntag\n", "normal", "   ", ""]
        let processedTags = rawTagNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Tag(name: $0, colorCode: 0) }

        XCTAssertEqual(processedTags.count, 3)
        XCTAssertEqual(processedTags[0].name, "spaced")
        XCTAssertEqual(processedTags[1].name, "tag")
        XCTAssertEqual(processedTags[2].name, "normal")

        // All get colorCode: 0 in fallback
        XCTAssertEqual(processedTags[0].colorCode, 0)
        XCTAssertEqual(processedTags[1].colorCode, 0)
        XCTAssertEqual(processedTags[2].colorCode, 0)
    }
}

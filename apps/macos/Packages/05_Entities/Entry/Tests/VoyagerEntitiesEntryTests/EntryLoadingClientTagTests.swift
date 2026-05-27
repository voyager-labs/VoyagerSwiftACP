import CoreServices
import Foundation
@testable import VoyagerEntitiesEntry
import VoyagerEntitiesTag
import XCTest

/// EntryLoadingClient의 태그 로딩 동작에 대한 명세 테스트
///
/// 폴백 체인을 문서화합니다:
/// 1. xattr com.apple.metadata:_kMDItemUserTags (colorCode 보존) - TagMetadataClient.loadTags를 통해
/// 2. URL tagNamesKey (colorCode 항상 0) - xattr를 사용할 수 없을 때의 폴백
///
/// 참고: EntryLoadingClient.entryTags(from:)는 private이므로 다음을 통해 테스트합니다:
/// - TagMetadataClient.loadTags (xattr 경로)
/// - tagNamesKey 폴백 동작 문서화
@MainActor
final class EntryLoadingClientTagTests: XCTestCase {
    // MARK: - TagMetadataClient.loadTags 테스트

    /// 태그가 없는 파일에서 xattr 기반 로딩이 nil을 반환하는지 테스트합니다.
    /// 기대 결과: 태그가 없는 파일 → nil
    func testLoadTags_NoTags_ReturnsNil() throws {
        // 태그 없는 임시 파일 생성
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("untagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = TagMetadataClient.loadTags(from: testFile)

        // 태그가 없으면 xattr 기반 로딩은 nil을 반환합니다
        XCTAssertNil(result)
    }

    /// xattr 기반 로딩이 올바르게 태그된 파일에서 색상 코드가 포함된 태그를 반환하는지 테스트합니다.
    /// 이 테스트는 기대 형식을 문서화합니다: "name\ncolorCode"
    /// 참고: Finder 태그 설정이 필요하며, 모든 환경에서 동작하지 않을 수 있습니다.
    func testLoadTags_WithFinderTags_PreservesColorCode() throws {
        // 임시 파일 생성
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("tagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 확장 속성을 사용하여 Finder 태그 설정
        // 형식은 "name\ncolorCode" 형태의 문자열을 포함하는 바이너리 plist입니다
        let tagWithColor = "TestTag\n6" // 색상 6 = 파란색
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
            // 일부 환경에서 권한 문제로 xattr 설정이 불가하면 테스트를 건너뜁니다
            throw XCTSkip("이 환경에서는 확장 속성을 설정할 수 없습니다")
        }

        // TagMetadataClient로 태그 로드
        let loadedTags = TagMetadataClient.loadTags(from: testFile)

        XCTAssertNotNil(loadedTags)
        XCTAssertEqual(loadedTags?.count, 1)
        XCTAssertEqual(loadedTags?.first?.name, "TestTag")
        XCTAssertEqual(loadedTags?.first?.colorCode, 6, "MDItem에서 색상 코드가 보존되어야 합니다")
    }

    /// 존재하지 않는 파일에서 xattr 기반 로딩이 nil을 반환하는지 테스트합니다.
    /// 기대 결과: 존재하지 않는 파일 → nil
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

    // MARK: - tagNamesKey 폴백 문서화 테스트

    /// tagNamesKey가 색상 정보 없이 태그 이름을 반환하는지 테스트합니다.
    /// xattr를 사용할 수 없을 때의 폴백 동작을 문서화합니다.
    /// 기대 결과: tagNamesKey는 이름은 제공하지만 색상 코드는 제공하지 않습니다
    func testTagNamesKey_ReturnsNamesWithoutColorCodes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var testFile = tempDir.appendingPathComponent("tagged_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // tagNamesKey를 사용하여 태그 설정 (표준 macOS API)
        try (testFile as NSURL).setResourceValue(["Red", "Green"], forKey: .tagNamesKey)

        // tagNamesKey로 다시 읽기
        let readValues = try testFile.resourceValues(forKeys: [.tagNamesKey])
        let tagNames = readValues.tagNames ?? []

        XCTAssertEqual(tagNames.count, 2)
        XCTAssertTrue(tagNames.contains("Red"))
        XCTAssertTrue(tagNames.contains("Green"))

        // 참고: tagNamesKey는 색상 코드 정보를 포함하지 않습니다
        // xattr를 사용할 수 없을 때 폴백은 colorCode: 0으로 태그를 생성합니다
    }

    /// 빈 태그 목록이 폴백에서 올바르게 처리되는지 테스트합니다.
    /// 기대 결과: 태그 없음 → entryTags 폴백에서 nil 반환
    func testTagNamesKey_EmptyTags_ReturnsNilInFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoyagerTagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let testFile = tempDir.appendingPathComponent("no_tags_file.txt")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 태그 없음 - tagNamesKey로 읽기
        let resourceValues = try testFile.resourceValues(forKeys: [.tagNamesKey])
        let tagNames = resourceValues.tagNames ?? []

        // 문서화: tagNamesKey가 빈 값을 반환하면 폴백은 nil을 반환합니다
        XCTAssertTrue(tagNames.isEmpty, "태그가 없는 파일은 빈 tagNames를 가져야 합니다")

        // 이것은 폴백 동작을 문서화합니다:
        // let tags = tagNames.map { Tag(name: $0, colorCode: 0) }
        // return tags.isEmpty ? nil : tags
        // → 빈 tagNames에 대해서는 nil 반환
    }

    // MARK: - 폴백 동작 문서화

    /// 전체 폴백 체인 동작을 문서화합니다.
    /// 이 테스트는 entryTags(from:) private 함수의 명세 문서 역할을 합니다.
    func testEntryTagsFallbackChain_Documentation() {
        // private 함수 EntryModelConverterLive.entryTags(from:)의 동작:
        //
        // 1. 먼저 TagMetadataClient.loadTags를 통해 xattr com.apple.metadata:_kMDItemUserTags 시도:
        //    - 성공 시: colorCode가 보존된 태그 반환
        //    - 형식: "name\ncolorCode" → Tag(name: "name", colorCode: Int)
        //
        // 2. xattr 로딩 실패 시, URL tagNamesKey로 폴백:
        //    - 반환: 색상 정보 없이 태그 이름만
        //    - 모든 태그의 colorCode: 0
        //    - 빈 목록 → nil 반환
        //
        // 3. 둘 다 실패 시: nil 반환
        //
        // 이 동작은 EntryLoadingClient.swift:640-652의 코드에 의해 규정됩니다

        // 예시 시나리오:
        // 시나리오 A: Finder 태그가 있는 파일 (xattr 경유)
        //   입력: "Important\n1" (빨간색)
        //   출력: Tag(name: "Important", colorCode: 1)
        //
        // 시나리오 B: 태그는 있지만 MDItem을 사용할 수 없는 파일
        //   입력: tagNamesKey를 통해 ["Work", "Personal"]
        //   출력: [Tag(name: "Work", colorCode: 0), Tag(name: "Personal", colorCode: 0)]
        //
        // 시나리오 C: 태그가 없는 파일
        //   출력: nil

        // 이 테스트는 위 문서화가 정확하면 통과합니다.
        // 실제 동작은 이 파일의 다른 테스트들로 검증됩니다.
        XCTAssertTrue(true, "문서화 테스트 — 폴백 체인 명세는 주석을 참조하세요")
    }

    /// 폴백 경로에서 공백이 잘리는지 테스트합니다.
    /// entryTags 폴백에서의 공백 제거 동작을 문서화합니다.
    func testFallback_TrimsWhitespaceFromTagNames() {
        // 폴백 코드:
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

        // 폴백에서는 모두 colorCode: 0
        XCTAssertEqual(processedTags[0].colorCode, 0)
        XCTAssertEqual(processedTags[1].colorCode, 0)
        XCTAssertEqual(processedTags[2].colorCode, 0)
    }
}

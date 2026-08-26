import Foundation
@testable import VoyagerHelper
import XCTest

@MainActor
final class SpotlightSearchEntryPackagePolicyTests: XCTestCase {
    // MARK: - EVM-001-reload_directory_page_on_external_change: deterministic classifier cells

    /// 검색 페이로드 package 분류를 결정하는 `SpotlightSearchService.isPackageDirectory`의 결정적 cell만 검증한다.
    /// `.voycoll` cell은 UTI 등록(`fm.voyager.collection`, `com.apple.package` conform)에 의존하므로
    /// machine-independent 단언으로부터 제외한다(아래 주석 참고).
    ///
    /// UTI-registration 의존 cell (test하지 않음): live probe 결과
    /// `UTType(filenameExtension: "voycoll") -> fm.voyager.collection, conformsToPackage: true`이므로
    /// Voyager가 설치된 machine에서는 `.voycoll` 디렉터리가 package로 분류된다.
    /// 그러나 이는 Info.plist의 UTI 등록 상태에 따라 달라지므로 이 테스트는 단언하지 않는다.
    private let sut = SpotlightSearchService()

    func testOrdinaryDirectoryIsNotPackage() throws {
        let directoryURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertFalse(sut.isPackageDirectory(directoryURL))
    }

    func testAppNamedDirectoryIsPackageByResolvedUTI() throws {
        // 시스템 SSOT에 위임된 분류기(`PackageDirectoryClassification`)가 Launch Services로
        // resolve한 UTI(`com.apple.application-bundle`)의 package 준수로 `.app`을 판정하는 결정적 cell.
        let directoryURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let appDirectoryURL = directoryURL.appendingPathComponent("Voyager.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true)

        XCTAssertTrue(sut.isPackageDirectory(appDirectoryURL))
    }

    func testPlainFileIsNotPackage() throws {
        let directoryURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("note.txt")
        try "note".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(sut.isPackageDirectory(fileURL))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

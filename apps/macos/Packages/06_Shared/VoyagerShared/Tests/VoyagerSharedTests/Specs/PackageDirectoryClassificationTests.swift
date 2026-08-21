import Foundation
@testable import VoyagerShared
import XCTest

final class PackageDirectoryClassificationTests: XCTestCase {
    // MARK: - VOY-594: delegated package classifier deterministic cells

    /// `PackageDirectoryClassification.isPackageDirectory`의 결정적 cell만 검증한다.
    /// 시스템 SSOT(package bit / resolved UTI)에 위임하므로, 이 테스트는 실행 환경에
    /// 의존하지 않는 fixture 기반 경로만 단언한다.
    private let sut = PackageDirectoryClassification.self

    func testOrdinaryDirectoryIsNotPackage() throws {
        let directoryURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertFalse(sut.isPackageDirectory(directoryURL))
    }

    func testVoycollNamedDirectoryIsPackageByDomainFallback() throws {
        // `.voycoll` 확장자는 도메인 fallback으로 자체 판정한다.
        // UTI 등록(`fm.voyager.collection`)은 Voyager 설치 머신에서만 유효하므로,
        // 미등록 환경/테스트 픽스처의 결정성을 위해 확장자로 판정한다.
        let directoryURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let voycollDirectoryURL = directoryURL.appendingPathComponent("Collection.voycoll", isDirectory: true)
        try FileManager.default.createDirectory(at: voycollDirectoryURL, withIntermediateDirectories: true)

        XCTAssertTrue(sut.isPackageDirectory(voycollDirectoryURL))
    }

    func testAppNamedDirectoryIsPackageByResolvedUTI() throws {
        // Launch Services가 `.app` 디렉터리를 `com.apple.application-bundle`로 resolve하여
        // package 준수로 판정되는 결정적 cell (테스트 프로세스 실측으로 안정 확인).
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

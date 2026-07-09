import Foundation
@testable import VoyagerFeaturesExternalFileRouter
import XCTest

final class FMW003FilePathNormalizerTests: XCTestCase {
    // MARK: - file URL → filesystem path

    /// file URL이 filesystem path로 올바르게 변환되는지 검증
    func testFileURLConvertsToPath() {
        let result = FilePathNormalizer.normalize("file:///Users/test/Documents")
        XCTAssertEqual(result, "/Users/test/Documents")
    }

    /// file URL의 percent-encoded 공백(%20)이 디코딩되는지 검증
    func testFileURLWithPercentEncodingDecodesSpace() {
        let result = FilePathNormalizer.normalize("file:///Users/test/My%20Documents")
        XCTAssertEqual(result, "/Users/test/My Documents")
    }

    /// file URL의 기타 percent-encoded 문자가 정상 디코딩되는지 검증
    func testFileURLWithSpecialCharactersDecodes() {
        let result = FilePathNormalizer.normalize("file:///Users/test/file%23name.txt")
        XCTAssertEqual(result, "/Users/test/file#name.txt")
    }

    // MARK: - trailing slash 정규화

    /// 일반 path의 trailing slash가 제거되는지 검증
    func testTrailingSlashRemoved() {
        let result = FilePathNormalizer.normalize("/Users/test/Documents/")
        XCTAssertEqual(result, "/Users/test/Documents")
    }

    /// file URL의 trailing slash가 제거되는지 검증
    func testFileURLTrailingSlashRemoved() {
        let result = FilePathNormalizer.normalize("file:///Users/test/Documents/")
        XCTAssertEqual(result, "/Users/test/Documents")
    }

    /// root path("/")의 trailing slash는 유지되는지 검증
    func testRootPathSlashPreserved() {
        let result = FilePathNormalizer.normalize("file:///")
        XCTAssertEqual(result, "/")
    }

    // MARK: - 빈 경로 처리

    /// 빈 문자열은 빈 문자열을 반환하는지 검증
    func testEmptyStringReturnsEmpty() {
        let result = FilePathNormalizer.normalize("")
        XCTAssertEqual(result, "")
    }

    /// 공백만 있는 문자열은 빈 문자열을 반환하는지 검증
    func testWhitespaceOnlyReturnsEmpty() {
        let result = FilePathNormalizer.normalize("   ")
        XCTAssertEqual(result, "")
    }

    // MARK: - path passthrough

    /// 이미 path인 입력은 그대로 표준화되어 반환되는지 검증
    func testPlainPathPassthrough() {
        let result = FilePathNormalizer.normalize("/usr/local/bin")
        XCTAssertEqual(result, "/usr/local/bin")
    }

    /// path 내부의 ".." 구성 요소가 정규화되는지 검증
    func testPathWithDotDotNormalized() {
        let result = FilePathNormalizer.normalize("/Users/test/../Documents")
        XCTAssertEqual(result, "/Users/Documents")
    }

    /// path 내부의 "." 구성 요소가 정규화되는지 검증
    func testPathWithDotNormalized() {
        let result = FilePathNormalizer.normalize("/Users/./test/Documents")
        XCTAssertEqual(result, "/Users/test/Documents")
    }
}

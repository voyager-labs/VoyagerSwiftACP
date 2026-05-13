import VoyagerShared
import XCTest

final class ByteSizeBucketTests: XCTestCase {
    // MARK: - Boundary tests

    func testZeroSizeReturnsZeroBytes() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: 0), .zeroBytes)
    }

    func testSizeOneReturnsLessThanHundredKB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: 1), .lessThanHundredKB)
    }

    func testExactlyHundredKBReturnsHundredKBToOneMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredKB), .hundredKBToOneMB)
    }

    func testExactlyOneMBReturnsOneMBToHundredMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneMB), .oneMBToHundredMB)
    }

    func testExactlyHundredMBReturnsHundredMBToOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredMB), .hundredMBToOneGB)
    }

    func testExactlyOneGBReturnsMoreThanOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneGB), .moreThanOneGB)
    }

    func testInt64MaxReturnsMoreThanOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: Int64.max), .moreThanOneGB)
    }

    // MARK: - CaseIterable

    func testAllCasesHasSixElements() {
        XCTAssertEqual(ByteSizeBucket.allCases.count, 6)
    }

    // MARK: - Just below each threshold

    func testJustBelowHundredKB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredKB - 1), .lessThanHundredKB)
    }

    func testJustBelowOneMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneMB - 1), .hundredKBToOneMB)
    }

    func testJustBelowHundredMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredMB - 1), .oneMBToHundredMB)
    }

    func testJustBelowOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneGB - 1), .hundredMBToOneGB)
    }
}

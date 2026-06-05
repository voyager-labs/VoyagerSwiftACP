import VoyagerShared
import XCTest

final class ByteSizeBucketTests: XCTestCase {
    // MARK: - 경계 테스트

    /// 0바이트는 zeroBytes로 분류되는지 검증
    func testZeroSizeReturnsZeroBytes() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: 0), .zeroBytes)
    }

    /// 1바이트는 가장 작은 비어 있지 않은 버킷으로 분류되는지 검증
    func testSizeOneReturnsLessThanHundredKB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: 1), .lessThanHundredKB)
    }

    /// 정확히 100KB 경계에서 다음 버킷으로 이동하는지 검증
    func testExactlyHundredKBReturnsHundredKBToOneMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredKB), .hundredKBToOneMB)
    }

    /// 정확히 1MB 경계에서 버킷이 바뀌는지 검증
    func testExactlyOneMBReturnsOneMBToHundredMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneMB), .oneMBToHundredMB)
    }

    /// 정확히 100MB 경계에서 다음 구간으로 분류되는지 검증
    func testExactlyHundredMBReturnsHundredMBToOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredMB), .hundredMBToOneGB)
    }

    /// 정확히 1GB부터 더 큰 버킷으로 분류되는지 검증
    func testExactlyOneGBReturnsMoreThanOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneGB), .moreThanOneGB)
    }

    /// 매우 큰 값도 상한 버킷으로 안정적으로 분류되는지 검증
    func testInt64MaxReturnsMoreThanOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: Int64.max), .moreThanOneGB)
    }

    // MARK: - CaseIterable(열거 가능한 시퀀스)

    /// CaseIterable 목록이 기대한 버킷 개수를 유지하는지 검증
    func testAllCasesHasSixElements() {
        XCTAssertEqual(ByteSizeBucket.allCases.count, 6)
    }

    // MARK: - 각 임계값 바로 아래

    /// 각 임계값 바로 아래 값이 이전 버킷에 남는지 검증
    func testJustBelowHundredKB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredKB - 1), .lessThanHundredKB)
    }

    /// 1MB 바로 아래 값이 중간 버킷에 남는지 검증
    func testJustBelowOneMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneMB - 1), .hundredKBToOneMB)
    }

    /// 100MB 바로 아래 값이 중간 상위 버킷에 남는지 검증
    func testJustBelowHundredMB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.hundredMB - 1), .oneMBToHundredMB)
    }

    /// 1GB 바로 아래 값이 1GB 미만 버킷에 남는지 검증
    func testJustBelowOneGB() {
        XCTAssertEqual(ByteSizeBucket.bucket(for: ByteSizeBucket.oneGB - 1), .hundredMBToOneGB)
    }
}

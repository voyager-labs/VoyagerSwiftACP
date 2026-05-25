@testable import Voyager
import XCTest

/// 위젯 동작의 회귀를 빠르게 검출하기 위한 테스트 모음이다.
@MainActor
final class EntryViewLayoutAutoscrollAccelTests: XCTestCase {
    /// 테스트 시나리오 회귀를 방지하기 위한 동작을 검증한다.
    func testDeltaIsZeroForZeroOrInvalidDistance() {
        let deltaZero = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 0, axisSize: 100)
        let deltaInfinity = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .infinity, axisSize: 100)
        let deltaNaN = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .nan, axisSize: 100)

        XCTAssertEqual(deltaZero, 0)
        XCTAssertEqual(deltaInfinity, 0)
        XCTAssertEqual(deltaNaN, 0)
    }

    /// 테스트 시나리오 회귀를 방지하기 위한 동작을 검증한다.
    func testDeltaSignMatchesDistanceSign() {
        let negative = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: -10, axisSize: 100)
        let positive = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 10, axisSize: 100)

        XCTAssertLessThan(negative, 0)
        XCTAssertGreaterThan(positive, 0)
    }

    /// 테스트 시나리오 회귀를 방지하기 위한 동작을 검증한다.
    func testDeltaIncreasesWithDistanceAndClamps() {
        let small = abs(EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 1, axisSize: 100))
        let medium = abs(EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 16, axisSize: 100))
        let large = abs(EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 64, axisSize: 100))
        let huge = abs(EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 10000, axisSize: 100))
        let vMax = EntryViewLayoutAutoscrollAcceleration.vMax
        let maxDelta = EntryViewLayoutAutoscrollAcceleration.maxDelta

        XCTAssertLessThan(small, medium)
        XCTAssertLessThan(medium, large)
        XCTAssertEqual(large, vMax)
        XCTAssertEqual(huge, vMax)
        XCTAssertLessThanOrEqual(huge, maxDelta)
    }
}

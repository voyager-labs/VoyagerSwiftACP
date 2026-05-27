@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutAutoscrollAccelTests: XCTestCase {
    /// 거리가 0, 무한대, NaN인 경우 delta가 0을 반환하는지 검증
    ///
    /// - 검증 내용: 유효하지 않은 거리 입력에 대해 자동 스크롤이 동작하지 않음
    /// - 회귀 방지: 경계 밖 마우스 좌표가 NaN/Infinity일 때 크래시나 잘못된 스크롤 방지
    func testDeltaIsZeroForZeroOrInvalidDistance() {
        let deltaZero = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 0, axisSize: 100)
        let deltaInfinity = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .infinity, axisSize: 100)
        let deltaNaN = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .nan, axisSize: 100)

        XCTAssertEqual(deltaZero, 0)
        XCTAssertEqual(deltaInfinity, 0)
        XCTAssertEqual(deltaNaN, 0)
    }

    /// delta 부호가 거리 부호와 일치하는지 검증 (위로 벗어나면 음수, 아래로 벗어나면 양수)
    func testDeltaSignMatchesDistanceSign() {
        let negative = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: -10, axisSize: 100)
        let positive = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 10, axisSize: 100)

        XCTAssertLessThan(negative, 0)
        XCTAssertGreaterThan(positive, 0)
    }

    /// 거리 증가에 따라 자동 스크롤 delta가 커지되 최대치에서 클램프되는지 검증
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

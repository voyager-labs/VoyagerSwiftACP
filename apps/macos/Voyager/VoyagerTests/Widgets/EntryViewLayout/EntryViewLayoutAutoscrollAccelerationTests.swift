@testable import Voyager
@testable import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class EntryViewLayoutAutoscrollAccelTests: XCTestCase {
    func testDeltaIsZeroForZeroOrInvalidDistance() {
        let deltaZero = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 0, axisSize: 100)
        let deltaInfinity = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .infinity, axisSize: 100)
        let deltaNaN = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: .nan, axisSize: 100)

        XCTAssertEqual(deltaZero, 0)
        XCTAssertEqual(deltaInfinity, 0)
        XCTAssertEqual(deltaNaN, 0)
    }

    func testDeltaSignMatchesDistanceSign() {
        let negative = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: -10, axisSize: 100)
        let positive = EntryViewLayoutAutoscrollAcceleration.delta(distanceOutsideBounds: 10, axisSize: 100)

        XCTAssertLessThan(negative, 0)
        XCTAssertGreaterThan(positive, 0)
    }

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

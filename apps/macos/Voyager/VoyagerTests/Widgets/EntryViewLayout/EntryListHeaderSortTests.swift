import CoreGraphics
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class EntryListHeaderSortTests: XCTestCase {
    func testHitZoneExcludesDividerProximityAndExpandsGapClicks() {
        let rects: [CGRect] = [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 108, y: 0, width: 100, height: 20),
        ]

        let dividerX = (rects[0].maxX + rects[1].minX) / 2
        XCTAssertNil(EntryListHeaderSortHitZone.columnIndexForSortClick(
            xPosition: dividerX,
            headerRects: rects,
            dividerExclusionWidth: 3,
        ))

        let epsilon: CGFloat = 0.01
        XCTAssertEqual(EntryListHeaderSortHitZone.columnIndexForSortClick(
            xPosition: rects[0].maxX + epsilon,
            headerRects: rects,
            dividerExclusionWidth: 3,
        ), 0)
        XCTAssertEqual(EntryListHeaderSortHitZone.columnIndexForSortClick(
            xPosition: rects[1].minX - epsilon,
            headerRects: rects,
            dividerExclusionWidth: 3,
        ), 1)
    }
}

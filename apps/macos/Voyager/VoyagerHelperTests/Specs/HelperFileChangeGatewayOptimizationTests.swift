import CoreServices
import Foundation
@testable import VoyagerHelper
import VoyagerShared
import XCTest

final class HelperFileChangeGatewayOptimizationTests: XCTestCase {
    func testWatchRootsApplyBroadRootGuardAndRootCap() {
        let roots = ["/", NSHomeDirectory()]
            + (0 ..< 70).map { "/tmp/voyager/root-\($0)" }
        let interest = FileChangeWatchInterest(
            id: "many-roots",
            owner: .collection,
            purpose: .collectionStale,
            roots: roots,
        )

        let cappedRoots = helperFileChangeGatewayWatchRoots(from: [interest])

        XCTAssertEqual(cappedRoots.count, FileChangeGatewayLimits.maxActiveWatchRoots)
        XCTAssertFalse(cappedRoots.contains("/"))
        XCTAssertFalse(cappedRoots.contains(FileChangeScopePolicy.normalizedPath(NSHomeDirectory())))
        XCTAssertEqual(cappedRoots, cappedRoots.sorted())
    }

    func testCoalescedEventsMergeFlagsByCanonicalPath() {
        let firstEvent = FileChangeGatewayEvent(
            path: "/tmp/voyager/demo/../demo/file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemCreated),
        )
        let secondEvent = FileChangeGatewayEvent(
            path: "/tmp/voyager/demo/file.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        let coalescedEvents = helperFileChangeGatewayCoalescedEvents([firstEvent, secondEvent])

        XCTAssertEqual(coalescedEvents.count, 1)
        XCTAssertEqual(coalescedEvents[0].path, "/tmp/voyager/demo/file.txt")
        XCTAssertNotEqual(coalescedEvents[0].flags & UInt32(kFSEventStreamEventFlagItemCreated), 0)
        XCTAssertNotEqual(coalescedEvents[0].flags & UInt32(kFSEventStreamEventFlagItemModified), 0)
    }

    func testOverflowCompactsEventsToAffectedRoots() {
        let interest = FileChangeWatchInterest(
            id: "storm",
            owner: .collection,
            purpose: .collectionStale,
            roots: ["/tmp/voyager/scope"],
        )
        let events = (0 ..< 20).map { index in
            FileChangeGatewayEvent(
                path: "/tmp/voyager/scope/file-\(index).txt",
                flags: UInt32(kFSEventStreamEventFlagItemCreated),
            )
        }

        let compactedEvents = helperFileChangeGatewayCompactedEvents(
            events,
            interests: [interest],
            maxEvents: 5,
        )

        XCTAssertEqual(compactedEvents.count, 1)
        XCTAssertEqual(compactedEvents[0].path, "/tmp/voyager/scope")
        XCTAssertNotEqual(compactedEvents[0].flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs), 0)
    }
}

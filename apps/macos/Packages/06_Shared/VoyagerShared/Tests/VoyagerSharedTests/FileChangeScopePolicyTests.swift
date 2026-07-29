import CoreServices
@testable import VoyagerShared
import XCTest

final class FileChangeScopePolicyTests: XCTestCase {
    func testInterestAffectedPathsResolvesSymlinkComponents() {
        let interest = FileChangeWatchInterest(
            id: "canonical-root",
            owner: .fileManager,
            purpose: .visibleFolderReload,
            roots: ["/var/tmp"],
            includeSubfolders: true,
        )
        let event = FileChangeGatewayEvent(
            path: "/private/var/tmp/voyager-helper-change.txt",
            flags: UInt32(kFSEventStreamEventFlagItemModified),
        )

        XCTAssertEqual(
            FileChangeScopePolicy.interestAffectedPaths(events: [event], interest: interest),
            [event.path],
        )
    }
}

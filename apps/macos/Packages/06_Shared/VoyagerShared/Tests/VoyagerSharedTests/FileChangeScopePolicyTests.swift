import CoreServices
@testable import VoyagerShared
import XCTest

final class FileChangeScopePolicyTests: XCTestCase {
    func testCanonicalPathStandardizesRelativeSymlinkDestination() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileChangeScopePolicyTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let parent = sandbox.appendingPathComponent("parent")
        let real = sandbox.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../real")

        XCTAssertEqual(
            FileChangeScopePolicy.canonicalPath(link.path),
            FileChangeScopePolicy.canonicalPath(real.path),
        )
        XCTAssertTrue(FileChangeScopePolicy.affects(
            root: link.path,
            path: real.appendingPathComponent("changed.txt").path,
            includeSubfolders: true,
        ))
    }

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

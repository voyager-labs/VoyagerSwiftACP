import AppKit
import Dependencies
@testable import VoyagerShared
import XCTest

@MainActor
final class WorkspaceClientTests: XCTestCase {
    func testIconForFileAsyncRunsResolverOffMainThread() async {
        let resolverWasMainThread = LockIsolated<Bool?>(nil)
        let expectedImage = NSImage(size: NSSize(width: 16, height: 16))
        var client = WorkspaceClient.testValue
        client.iconForFile = { _ in
            resolverWasMainThread.setValue(Thread.isMainThread)
            return expectedImage
        }

        let image = await client.iconForFileAsync("/tmp/example")

        XCTAssertFalse(resolverWasMainThread.value ?? true)
        XCTAssertIdentical(image, expectedImage)
    }
}

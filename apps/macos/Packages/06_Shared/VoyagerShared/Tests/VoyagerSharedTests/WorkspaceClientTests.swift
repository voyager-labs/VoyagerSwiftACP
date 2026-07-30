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

    func testPrepareFileIconsPublishesStrongSynchronousFinalIcon() async throws {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let client = WorkspaceClient.liveValue

        XCTAssertNil(client.cachedIconForFile(directory))
        let firstPreparationSucceeded = await client.prepareFileIcons([directory, directory])
        XCTAssertTrue(firstPreparationSucceeded)
        let firstIcon = try XCTUnwrap(client.cachedIconForFile(directory))
        XCTAssertGreaterThan(firstIcon.representations.first?.pixelsWide ?? 0, 0)
        XCTAssertGreaterThan(firstIcon.representations.first?.pixelsHigh ?? 0, 0)

        let secondPreparationSucceeded = await client.prepareFileIcons([directory])
        XCTAssertTrue(secondPreparationSucceeded)
        XCTAssertIdentical(client.cachedIconForFile(directory), firstIcon)
    }
}

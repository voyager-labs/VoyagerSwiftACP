import Foundation
@testable import VoyagerHelper
import XCTest

@MainActor
final class HelperExternalFileChangeBridgeTests: XCTestCase {
    func testPublishChangedPathsPostsLiveNotificationAndCoalescesStore() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = HelperExternalFileChangeStore(
            payloadURL: tempDirectory.appendingPathComponent("payload.json"),
            lockURL: tempDirectory.appendingPathComponent("payload.lock"),
        )
        let bridge = HelperExternalFileChangeBridge(store: store)

        let payload = await expectNotification(named: .voyagerHelperFSChanged) {
            Task { @MainActor in
                await bridge.publishChangedPaths(["/tmp/demo/a", "/tmp/demo/../demo/a", "/tmp/demo/b"])
            }
        }

        XCTAssertEqual(
            payload?.paths,
            HelperExternalFileChangePayload.canonicalPaths(["/tmp/demo/a", "/tmp/demo/b"]),
        )

        let stored = try await store.load()
        XCTAssertEqual(stored?.paths, payload?.paths)
    }

    func testReplayRequestReturnsPersistedPayloadAndConsumesWhenRequested() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = HelperExternalFileChangeStore(
            payloadURL: tempDirectory.appendingPathComponent("payload.json"),
            lockURL: tempDirectory.appendingPathComponent("payload.lock"),
        )
        let bridge = HelperExternalFileChangeBridge(store: store)
        bridge.startObservingReplayRequests()

        _ = try await store.coalesce(["/tmp/demo/a", "/tmp/demo/b"])

        let replay = await expectNotification(named: .voyagerHelperFSReplay) {
            DistributedNotificationCenter.default().post(
                name: .voyagerHelperFSReplayRequest,
                object: nil,
                userInfo: HelperExternalFileChangeReplayRequest(consume: true).asUserInfo(),
            )
        }

        XCTAssertEqual(
            replay?.paths,
            HelperExternalFileChangePayload.canonicalPaths(["/tmp/demo/a", "/tmp/demo/b"]),
        )

        let afterConsume = try await store.load()
        XCTAssertNil(afterConsume)
    }

    func testReplayAckRemovesOnlyAcknowledgedPaths() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = HelperExternalFileChangeStore(
            payloadURL: tempDirectory.appendingPathComponent("payload.json"),
            lockURL: tempDirectory.appendingPathComponent("payload.lock"),
        )
        let bridge = HelperExternalFileChangeBridge(store: store)
        bridge.startObservingReplayRequests()

        _ = try await store.coalesce(["/tmp/demo/a", "/tmp/demo/b", "/tmp/demo/c"])

        DistributedNotificationCenter.default().post(
            name: .voyagerHelperFSReplayAck,
            object: nil,
            userInfo: HelperExternalFileChangePayload(paths: ["/tmp/demo/a", "/tmp/demo/c"]).asUserInfo(),
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let remaining = try await store.load()
        XCTAssertEqual(remaining?.paths, ["/tmp/demo/b"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func expectNotification(
        named name: Notification.Name,
        operation: () -> Void,
    ) async -> HelperExternalFileChangePayload? {
        let center = DistributedNotificationCenter.default()
        let expectation = expectation(description: name.rawValue)
        var payload: HelperExternalFileChangePayload?

        let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            payload = HelperExternalFileChangePayload.from(userInfo: notification.userInfo)
            expectation.fulfill()
        }

        operation()
        await fulfillment(of: [expectation], timeout: 2)
        center.removeObserver(token)
        return payload
    }
}

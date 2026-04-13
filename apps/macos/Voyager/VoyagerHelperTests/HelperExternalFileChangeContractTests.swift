import Foundation
@testable import VoyagerHelper
import XCTest

final class HelperExternalFileChangeContractTests: XCTestCase {
    func testPayloadNormalizesAndDeduplicatesPaths() {
        let payload = HelperExternalFileChangePayload(
            paths: [
                "/tmp/demo/../demo/file.txt",
                "/tmp/demo/file.txt",
                "/tmp/demo/sub/../other.txt",
            ],
            generatedAt: Date(timeIntervalSince1970: 123),
        )

        XCTAssertEqual(
            payload.paths,
            HelperExternalFileChangePayload.canonicalPaths([
                "/tmp/demo/file.txt",
                "/tmp/demo/other.txt",
            ]),
        )
    }

    func testReplayRequestRoundTripsThroughUserInfo() {
        let request = HelperExternalFileChangeReplayRequest(consume: true)

        let roundTrip = HelperExternalFileChangeReplayRequest.from(userInfo: request.asUserInfo())

        XCTAssertEqual(roundTrip, request)
    }

    func testPayloadRoundTripsThroughUserInfo() {
        let date = Date(timeIntervalSince1970: 456)
        let payload = HelperExternalFileChangePayload(paths: ["/tmp/a", "/tmp/b"], generatedAt: date)

        let roundTrip = HelperExternalFileChangePayload.from(userInfo: payload.asUserInfo())

        XCTAssertEqual(roundTrip, payload)
    }

    func testPayloadJSONUsesSnakeCaseSchema() throws {
        let date = Date(timeIntervalSince1970: 789)
        let payload = HelperExternalFileChangePayload(paths: ["/tmp/a"], generatedAt: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertEqual(json["paths"] as? [String], HelperExternalFileChangePayload.canonicalPaths(["/tmp/a"]))
        XCTAssertNotNil(json["generated_at"])
        XCTAssertNil(json["schemaVersion"])
        XCTAssertNil(json["generatedAt"])
    }

    func testPersistenceLocationIsDeterministic() {
        let homeDirectoryURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let first = HelperExternalFSLocation.payloadFileURL(homeDirectoryURL: homeDirectoryURL)
        let second = HelperExternalFSLocation.payloadFileURL(homeDirectoryURL: homeDirectoryURL)
        let lockURL = HelperExternalFSLocation.lockFileURL(homeDirectoryURL: homeDirectoryURL)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.path,
            "/Users/tester/Library/Application Support/Voyager/helper_external_file_changes.json",
        )
        XCTAssertEqual(first.lastPathComponent, "helper_external_file_changes.json")
        XCTAssertEqual(lockURL.lastPathComponent, "helper_external_file_changes.lock")
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "Voyager")
        XCTAssertEqual(lockURL.deletingLastPathComponent(), first.deletingLastPathComponent())
    }

    func testCorruptedPayloadIsQuarantinedAndReplayRecovers() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let payloadURL = temporaryDirectory.appendingPathComponent("helper_external_file_changes.json")
        let lockURL = temporaryDirectory.appendingPathComponent("helper_external_file_changes.lock")
        let store = HelperExternalFileChangeStore(payloadURL: payloadURL, lockURL: lockURL)

        try Data("not-json".utf8).write(to: payloadURL, options: .atomic)

        let loaded = try await store.load()
        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        XCTAssertTrue(files.contains { $0.hasPrefix("helper_external_file_changes.corrupted-") })
    }

    func testStoreReplayPeekDoesNotClear() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = makeStore(in: temporaryDirectory)
        _ = try await store.coalesce(["/tmp/demo/a"])

        let replay = try await store.payloadForReplay(.init(consume: false))
        let stillPending = try await store.load()

        XCTAssertEqual(replay, stillPending)
    }

    func testStoreReplayConsumeClears() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = makeStore(in: temporaryDirectory)
        let written = try await store.coalesce(["/tmp/demo/a", "/tmp/demo/../demo/a"])

        let consumed = try await store.payloadForReplay(.init(consume: true))
        let afterConsume = try await store.load()

        XCTAssertEqual(consumed, written)
        XCTAssertNil(afterConsume)
    }

    func testEmptyCoalesceIsNoOp() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = makeStore(in: temporaryDirectory)

        let result = try await store.coalesce([])
        let loaded = try await store.load()

        XCTAssertNil(result)
        XCTAssertNil(loaded)
    }

    func testConcurrentStoresDoNotDropUpdatesAcrossConsumeAndCoalesce() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let firstStore = makeStore(in: temporaryDirectory)
        let secondStore = makeStore(in: temporaryDirectory)

        _ = try await firstStore.coalesce(["/tmp/demo/a"])

        async let consumed = firstStore.payloadForReplay(.init(consume: true))
        async let recoalesced = secondStore.coalesce(["/tmp/demo/b"])

        let consumedPayload = try await consumed
        let recoalescedPayload = try await recoalesced
        let pendingPayload = try await secondStore.load()
        let deliveredPaths = Set((consumedPayload?.paths ?? []) + (pendingPayload?.paths ?? []))

        XCTAssertTrue(deliveredPaths.contains(HelperExternalFileChangePayload.canonicalPaths(["/tmp/demo/a"])[0]))
        XCTAssertTrue(deliveredPaths.contains(HelperExternalFileChangePayload.canonicalPaths(["/tmp/demo/b"])[0]))
        XCTAssertNotNil(recoalescedPayload)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeStore(in directory: URL) -> HelperExternalFileChangeStore {
        HelperExternalFileChangeStore(
            payloadURL: directory.appendingPathComponent("helper_external_file_changes.json"),
            lockURL: directory.appendingPathComponent("helper_external_file_changes.lock"),
        )
    }
}

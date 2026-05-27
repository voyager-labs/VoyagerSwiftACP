import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

/// 컬렉션 유효기간 클라이언트 — 무효화/소비, 범위 업데이트, 마이그레이션 호환성을 검증.
@MainActor
final class CollectionStalenessClientTests: XCTestCase {
    func testInvalidateAndConsumeClosedCollectionRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sub/a.txt"])
        XCTAssertTrue(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testRegisterCollectionClearsExistingInvalidationState() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let path = "/tmp/voyager/sample.voycoll"

        client.upsertRecord(
            path,
            .init(
                definitionFingerprint: "fp",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantPast,
            ),
        )

        client.registerCollection(path, ["/tmp/voyager"])

        XCTAssertNil(client.record(path)?.lastInvalidatedAt)
    }

    func testUnrelatedPathDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/other/a.txt"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testCollectionDocumentPathDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sample.voycoll"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testCollectionPackagePayloadWriteDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager/sample.voycoll/collection.plist"])
        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testSuppressedParentDirectoryPathDoesNotInvalidateClosedCollectionRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])
        client.suppressPaths(["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager"])

        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testSuppressedParentDirectoryPathIgnoresRepeatedEvents() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        client.registerCollection("/tmp/voyager/sample.voycoll", ["/tmp/voyager"])
        client.suppressPaths(["/tmp/voyager"])

        client.invalidateRecords(["/tmp/voyager"])
        client.invalidateRecords(["/tmp/voyager"])
        client.invalidateRecords(["/tmp/voyager"])

        XCTAssertFalse(client.consumeInvalidation("/tmp/voyager/sample.voycoll"))
    }

    func testUpsertAndReloadRecord() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let path = "/tmp/test.voycoll"
        let record = CollectionStalenessRecord(
            definitionFingerprint: "fp",
            relevanceRoots: ["/tmp/root"],
            lastInvalidatedAt: nil,
        )

        client.upsertRecord(path, record)

        XCTAssertEqual(client.record(path), record)
    }

    func testInvalidateRecordsTouchesOnlyMatchingRoots() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)

        client.upsertRecord(
            "/tmp/a.voycoll",
            .init(definitionFingerprint: "a", relevanceRoots: ["/tmp/root-a"], lastInvalidatedAt: nil),
        )
        client.upsertRecord(
            "/tmp/b.voycoll",
            .init(definitionFingerprint: "b", relevanceRoots: ["/tmp/root-b"], lastInvalidatedAt: nil),
        )

        client.invalidateRecords(["/tmp/root-a/child/file.txt"])

        XCTAssertNotNil(client.record("/tmp/a.voycoll")?.lastInvalidatedAt)
        XCTAssertNil(client.record("/tmp/b.voycoll")?.lastInvalidatedAt)
    }

    func testClearRecordRemovesStoredValue() {
        let client = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let path = "/tmp/test.voycoll"
        client.upsertRecord(
            path,
            .init(definitionFingerprint: "fp", relevanceRoots: ["/tmp/root"], lastInvalidatedAt: nil),
        )

        client.clearRecord(path)

        XCTAssertNil(client.record(path))
    }

    /// testLegacyJSONStorageMigratesAndPreservesInvalidatedState 테스트 동작을 검증한다.
    func testLegacyJSONStorageMigratesAndPreservesInvalidatedState() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionStalenessClient.live(userDefaultsClient: userDefaultsClient)
        let path = "/tmp/legacy/sample.voycoll"

        let legacy = [
            path: LegacyStorageRecord(scopes: ["/tmp/legacy"], isInvalidated: true),
        ]
        let data = try JSONEncoder().encode(legacy)
        userDefaultsClient.setObject(data, CollectionKeys.stalenessRecords)

        let record = client.record(path)

        XCTAssertEqual(record?.definitionFingerprint, "")
        XCTAssertEqual(record?.relevanceRoots, ["/tmp/legacy"])
        XCTAssertNotNil(record?.lastInvalidatedAt)

        let migratedData = try XCTUnwrap(userDefaultsClient.object(CollectionKeys.stalenessRecords) as? Data)
        let migrated = try PropertyListDecoder().decode([String: CollectionStalenessRecord].self, from: migratedData)
        XCTAssertEqual(migrated[path]?.relevanceRoots, ["/tmp/legacy"])
        XCTAssertNotNil(migrated[path]?.lastInvalidatedAt)
    }

    /// testConsumeInvalidationStillWorksAfterLegacyMigration 테스트 동작을 검증한다.
    func testConsumeInvalidationStillWorksAfterLegacyMigration() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionStalenessClient.live(userDefaultsClient: userDefaultsClient)
        let path = "/tmp/legacy/sample.voycoll"

        let legacy = [
            path: LegacyStorageRecord(scopes: ["/tmp/legacy"], isInvalidated: true),
        ]
        try userDefaultsClient.setObject(JSONEncoder().encode(legacy), CollectionKeys.stalenessRecords)

        XCTAssertTrue(client.consumeInvalidation(path))
        XCTAssertFalse(client.consumeInvalidation(path))
    }

    private struct LegacyStorageRecord: Codable {
        let scopes: [String]
        let isInvalidated: Bool
    }
}

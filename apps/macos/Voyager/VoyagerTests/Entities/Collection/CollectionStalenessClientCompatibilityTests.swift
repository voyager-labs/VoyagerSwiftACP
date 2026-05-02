import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionStalenessCompatTests: XCTestCase {
    func testLegacyPropertyListStorageMigratesAndPreservesInvalidatedState() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionStalenessClient.live(userDefaultsClient: userDefaultsClient)
        let path = "/tmp/legacy/sample.voycoll"

        let legacy = [
            path: LegacyStorageRecord(scopes: ["/tmp/legacy"], isInvalidated: true),
        ]
        let data = try PropertyListEncoder().encode(legacy)
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

    func testMissingFieldCurrentRecordDecodesWithDefaults() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionStalenessClient.live(userDefaultsClient: userDefaultsClient)
        let path = "/tmp/missing-fields/sample.voycoll"

        let payload: [String: [String: Any]] = [
            path: [
                "relevanceRoots": ["/tmp/root"],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        userDefaultsClient.setObject(data, CollectionKeys.stalenessRecords)

        let record = client.record(path)
        XCTAssertEqual(record?.definitionFingerprint, "")
        XCTAssertEqual(record?.relevanceRoots, ["/tmp/root"])
        XCTAssertEqual(record?.excludedScopes, [])
        XCTAssertNil(record?.lastInvalidatedAt)
    }

    func testMixedShapePayloadKeepsValidRecordAndDropsMalformedEntry() throws {
        let userDefaultsClient = UserDefaultsClient.testValue
        let client = CollectionStalenessClient.live(userDefaultsClient: userDefaultsClient)

        let validPath = "/tmp/valid/sample.voycoll"
        let invalidPath = "/tmp/invalid/sample.voycoll"
        let payload: [String: Any] = [
            validPath: [
                "definitionFingerprint": "fp",
                "relevanceRoots": ["/tmp/root"],
            ],
            invalidPath: "garbage",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        userDefaultsClient.setObject(data, CollectionKeys.stalenessRecords)

        XCTAssertEqual(client.record(validPath)?.definitionFingerprint, "fp")
        XCTAssertEqual(client.record(validPath)?.relevanceRoots, ["/tmp/root"])
        XCTAssertNil(client.record(invalidPath))
    }

    private struct LegacyStorageRecord: Codable {
        let scopes: [String]
        let isInvalidated: Bool
    }
}

@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotHydrationTests: XCTestCase {
    func testNilSnapshotReturnsNil() {
        let file = VoyagerCollectionFile(
            id: "no-snapshot",
            name: "No Snapshot",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNil(response)
    }

    func testMismatchFingerprintReturnsNil() {
        let file = VoyagerCollectionFile(
            id: "mismatch",
            name: "Mismatch",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: "report",
            scopes: ["/tmp"],
            conditions: [],
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: "different-fingerprint",
                capturedAt: Date.distantPast,
                itemCount: 1,
                relevanceRoots: ["/tmp"]
            ),
            appVersion: nil
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNil(response)
    }

    func testUsableSnapshotBuildsSyntheticSearchResponse() {
        let query = "report"
        let scopes = ["/tmp"]
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]

        let fingerprint = CollectionSnapshotHydration.definitionFingerprint(
            query: query,
            scopes: scopes,
            conditions: conditions
        )

        let file = VoyagerCollectionFile(
            id: "test",
            name: "Test",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: query,
            scopes: scopes,
            conditions: conditions,
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: fingerprint,
                capturedAt: Date.distantPast,
                itemCount: 1,
                relevanceRoots: scopes
            ),
            appVersion: nil
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.itemCount, 1)
        XCTAssertEqual(response?.items, [VoyagerShared.JSONValue.string("/tmp/report.txt")])
        XCTAssertEqual(response?.appliedFilters?.scopes, scopes)
        XCTAssertEqual(response?.appliedFilters?.conditions, [
            .init(propertyKey: "name_full", operator: "eq", value: .string("report")),
        ])
    }

    func testDefinitionFingerprintConsistency() {
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]

        let fp1 = CollectionSnapshotHydration.definitionFingerprint(
            query: " report ",
            scopes: ["/tmp"],
            conditions: conditions
        )

        let file = VoyagerCollectionFile(
            id: "test",
            name: "Test",
            createdAt: Date.distantPast,
            updatedAt: Date.distantFuture,
            query: " report ",
            scopes: ["/tmp"],
            conditions: conditions,
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil
        )

        let fp2 = CollectionSnapshotHydration.definitionFingerprint(file: file)

        XCTAssertEqual(fp1, fp2)
    }
}

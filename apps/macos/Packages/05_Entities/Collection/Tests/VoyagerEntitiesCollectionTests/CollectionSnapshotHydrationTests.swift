@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotHydrationTests: XCTestCase {
    /// 스냅샷이 없으면 복원 가능한 synthetic response도 없다는 점을 검증
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
            appVersion: nil,
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNil(response)
    }

    /// fingerprint가 다르면 스냅샷을 복원하지 않는 안전장치를 검증
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
                relevanceRoots: ["/tmp"],
            ),
            appVersion: nil,
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNil(response)
    }

    /// 유효한 스냅샷은 synthetic search response로 복원되는지 검증
    func testUsableSnapshotBuildsSyntheticSearchResponse() {
        let query = "report"
        let scopes = ["/tmp"]
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]

        let fingerprint = CollectionSnapshotHydration.definitionFingerprint(
            query: query,
            scopes: scopes,
            includeDirectories: true,
            conditions: conditions,
        )

        let file = VoyagerCollectionFile(
            id: "test",
            name: "Test",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: query,
            scopes: scopes,
            includeDirectories: true,
            conditions: conditions,
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: fingerprint,
                capturedAt: Date.distantPast,
                itemCount: 1,
                relevanceRoots: scopes,
            ),
            appVersion: nil,
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.itemCount, 1)
        XCTAssertEqual(response?.items, [VoyagerShared.JSONValue.string("/tmp/report.txt")])
        XCTAssertEqual(response?.appliedFilters?.scopes, scopes)
        XCTAssertEqual(response?.appliedFilters?.includeDirectories, true)
        XCTAssertEqual(response?.appliedFilters?.conditions, [
            .init(propertyKey: "name_full", operator: "eq", value: .string("report")),
        ])
    }

    /// 정의 fingerprint 계산이 파일/인자 기반 계산과 일치하는지 검증
    func testDefinitionFingerprintConsistency() {
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]

        let fp1 = CollectionSnapshotHydration.definitionFingerprint(
            query: " report ",
            scopes: ["/tmp"],
            conditions: conditions,
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
            appVersion: nil,
        )

        let fp2 = CollectionSnapshotHydration.definitionFingerprint(file: file)

        XCTAssertEqual(fp1, fp2)
    }

    /// directory 포함 정책이 다르면 snapshot fingerprint도 달라지는지 검증
    func testDefinitionFingerprintIncludesDirectoryPolicy() {
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "tag_names", operatorCode: "any", value: .array([.string("Work")])),
        ]

        let excludingDirectories = CollectionSnapshotHydration.definitionFingerprint(
            query: "",
            scopes: ["/"],
            includeDirectories: false,
            conditions: conditions,
        )
        let includingDirectories = CollectionSnapshotHydration.definitionFingerprint(
            query: "",
            scopes: ["/"],
            includeDirectories: true,
            conditions: conditions,
        )

        XCTAssertNotEqual(excludingDirectories, includingDirectories)
    }
}

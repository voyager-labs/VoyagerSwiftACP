import CryptoKit
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

    /// includeDirectories 도입 전 fingerprint도 directory 미포함 collection이면 호환 복원되는지 검증
    func testUsableSnapshotAcceptsLegacyFingerprintBeforeDirectoryPolicy() {
        let query = "report"
        let scopes = ["/tmp"]
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]
        let legacyFingerprint = legacyDefinitionFingerprintBeforeDirectoryPolicy(
            query: query,
            scopes: scopes,
            excludedScopes: [],
            includeSubfolders: true,
            conditions: conditions,
        )
        let file = VoyagerCollectionFile(
            id: "legacy",
            name: "Legacy",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: query,
            scopes: scopes,
            includeDirectories: false,
            conditions: conditions,
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp/report.txt")]),
            snapshotMeta: .init(
                definitionFingerprint: legacyFingerprint,
                capturedAt: Date.distantPast,
                itemCount: 1,
                relevanceRoots: scopes,
            ),
            appVersion: nil,
        )

        XCTAssertNotNil(CollectionSnapshotHydration.usableSnapshot(for: file))
    }

    /// directory 포함 collection은 includeDirectories 이전 fingerprint로 복원하지 않는지 검증
    func testUsableSnapshotRejectsLegacyFingerprintWhenDirectoriesAreIncluded() {
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "tag_names", operatorCode: "any", value: .array([.string("Work")])),
        ]
        let legacyFingerprint = legacyDefinitionFingerprintBeforeDirectoryPolicy(
            query: "",
            scopes: ["/"],
            excludedScopes: [],
            includeSubfolders: true,
            conditions: conditions,
        )
        let file = VoyagerCollectionFile(
            id: "legacy-tags",
            name: "Legacy Tags",
            createdAt: Date.distantPast,
            updatedAt: Date.distantPast,
            query: "",
            scopes: ["/"],
            includeDirectories: true,
            conditions: conditions,
            snapshot: .init(items: [VoyagerShared.JSONValue.string("/tmp")]),
            snapshotMeta: .init(
                definitionFingerprint: legacyFingerprint,
                capturedAt: Date.distantPast,
                itemCount: 1,
                relevanceRoots: ["/"],
            ),
            appVersion: nil,
        )

        XCTAssertNil(CollectionSnapshotHydration.usableSnapshot(for: file))
    }

    private func legacyDefinitionFingerprintBeforeDirectoryPolicy(
        query: String,
        scopes: [String],
        excludedScopes: [String],
        includeSubfolders: Bool,
        conditions: [CollectionCondition],
    ) -> String {
        let normalizedConditions = conditions
            .map { condition in
                let value = legacyCanonicalValueString(condition.value)
                return [condition.propertyKey, condition.operatorCode, value].joined(separator: "\u{1E}")
            }
            .sorted()
        let canonical = [
            query.trimmingCharacters(in: .whitespacesAndNewlines),
            scopes.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted().joined(separator: "\u{1D}"),
            excludedScopes.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted().joined(separator: "\u{1E}"),
            includeSubfolders ? "includeSubfolders:true" : "includeSubfolders:false",
            normalizedConditions.joined(separator: "\u{1C}"),
        ].joined(separator: "\u{1B}")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func legacyCanonicalValueString(_ value: VoyagerShared.JSONValue?) -> String {
        guard let value else { return "null" }
        switch value {
        case let .string(string):
            return "s:\(string)"
        case let .number(number):
            return "n:\(number)"
        case let .bool(bool):
            return bool ? "b:true" : "b:false"
        case let .array(values):
            return "a:[\(values.map { legacyCanonicalValueString($0) }.joined(separator: ","))]"
        case let .object(values):
            let entries = values
                .map { key, value in "\(key)=\(legacyCanonicalValueString(value))" }
                .sorted()
                .joined(separator: ",")
            return "o:{\(entries)}"
        case .null:
            return "null"
        }
    }

}

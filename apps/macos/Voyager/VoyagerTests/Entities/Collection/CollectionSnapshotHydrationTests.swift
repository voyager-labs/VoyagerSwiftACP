import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotHydrationTests: XCTestCase {
    func testUsableSnapshotBuildsSyntheticSearchResponse() {
        let conditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
        ]
        let file = makeSnapshotFile(
            query: " report ",
            scopes: ["/tmp"],
            conditions: conditions,
            snapshotItems: [.string("/tmp/report.txt")],
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertEqual(response?.itemCount, 1)
        XCTAssertEqual(response?.items, [.string("/tmp/report.txt")])
        XCTAssertEqual(response?.appliedFilters?.scopes, ["/tmp"])
        XCTAssertEqual(response?.appliedFilters?.excludedScopes, [])
        XCTAssertEqual(response?.appliedFilters?.includeSubfolders, true)
        XCTAssertEqual(response?.appliedFilters?.conditions, [
            .init(propertyKey: "name_full", operator: "eq", value: .string("report")),
        ])
    }

    func testSyntheticSearchResponsePreservesIncludeSubfoldersFlag() {
        let file = makeSnapshotFile(
            query: "report",
            scopes: ["/tmp"],
            includeSubfolders: false,
            conditions: [],
            snapshotItems: [.string("/tmp/report.txt")],
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertEqual(response?.appliedFilters?.includeSubfolders, false)
    }

    func testSyntheticSearchResponsePreservesExcludedScopes() {
        let file = makeSnapshotFile(
            query: "report",
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/ignored"],
            conditions: [],
            snapshotItems: [.string("/tmp/report.txt")],
        )

        let response = CollectionSnapshotHydration.syntheticSearchResponse(for: file)

        XCTAssertEqual(response?.appliedFilters?.excludedScopes, ["/tmp/ignored"])
    }

    func testFingerprintMismatchMarksSnapshotUnusable() {
        let file = makeSnapshotFile(
            query: "report",
            scopes: ["/tmp"],
            conditions: [.init(propertyKey: "name_full", operatorCode: "eq", value: .string("report"))],
            snapshotItems: [.string("/tmp/report.txt")],
            fingerprint: "different",
        )

        XCTAssertNil(CollectionSnapshotHydration.usableSnapshot(for: file))
        XCTAssertNil(CollectionSnapshotHydration.syntheticSearchResponse(for: file))
    }

    func testDefinitionFingerprintMatchesConditionAndCollectionConditionForms() {
        let uiConditions = makeUIConditions()

        let persistedConditions: [CollectionCondition] = [
            .init(propertyKey: "name_full", operatorCode: "eq", value: .string("report")),
            .init(propertyKey: "size", operatorCode: "eq", value: .number(12)),
        ]

        let fromUI = CollectionSnapshotHydration.definitionFingerprint(
            query: "report",
            scopes: ["/b", "/a"],
            conditions: uiConditions,
        )
        let fromFile = CollectionSnapshotHydration.definitionFingerprint(
            query: " report ",
            scopes: ["/a", "/b"],
            conditions: persistedConditions,
        )

        XCTAssertEqual(fromUI, fromFile)
    }

    func testDefinitionFingerprintChangesWhenIncludeSubfoldersChanges() {
        let conditions = makeUIConditions()

        let recursive = CollectionSnapshotHydration.definitionFingerprint(
            query: "report",
            scopes: ["/tmp"],
            includeSubfolders: true,
            conditions: conditions,
        )
        let exact = CollectionSnapshotHydration.definitionFingerprint(
            query: "report",
            scopes: ["/tmp"],
            includeSubfolders: false,
            conditions: conditions,
        )

        XCTAssertNotEqual(recursive, exact)
    }

    func testDefinitionFingerprintChangesWhenExcludedScopesChange() {
        let conditions = makeUIConditions()

        let withoutExcluded = CollectionSnapshotHydration.definitionFingerprint(
            query: "report",
            scopes: ["/tmp"],
            excludedScopes: [],
            conditions: conditions,
        )
        let withExcluded = CollectionSnapshotHydration.definitionFingerprint(
            query: "report",
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/ignored"],
            conditions: conditions,
        )

        XCTAssertNotEqual(withoutExcluded, withExcluded)
    }
}

private func makeUIConditions() -> [Condition] {
    [
        makeCondition(
            propertyKey: "size",
            propertyLabel: "Size",
            valueType: "number",
            values: ["12"],
            isActive: true,
        ),
        makeCondition(
            propertyKey: "name_full",
            propertyLabel: "Name",
            valueType: "string",
            values: ["report"],
            isActive: true,
        ),
        makeCondition(
            propertyKey: "ignored",
            propertyLabel: "Ignored",
            valueType: "string",
            values: ["inactive"],
            isActive: false,
        ),
    ]
}

private func makeCondition(
    propertyKey: String,
    propertyLabel: String,
    valueType: String,
    values: [String],
    isActive: Bool,
) -> Condition {
    .init(
        propertyKey: propertyKey,
        propertyLabel: propertyLabel,
        propertyType: "metadata",
        operatorCode: "eq",
        operatorLabel: "is",
        operatorValueArity: 1,
        operatorValueUIKind: nil,
        valueType: valueType,
        values: values,
        isActive: isActive,
    )
}

private func makeSnapshotFile(
    query: String,
    scopes: [String],
    excludedScopes: [String] = [],
    includeSubfolders: Bool = true,
    conditions: [CollectionCondition],
    snapshotItems: [JSONValue],
    fingerprint: String? = nil,
) -> VoyagerCollectionFile {
    let resolvedFingerprint = fingerprint
        ?? CollectionSnapshotHydration.definitionFingerprint(
            query: query,
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            conditions: conditions,
        )

    return VoyagerCollectionFile(
        id: "snapshot",
        name: "Snapshot",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        query: query,
        scopes: scopes,
        excludedScopes: excludedScopes,
        includeSubfolders: includeSubfolders,
        conditions: conditions,
        snapshot: .init(items: snapshotItems),
        snapshotMeta: .init(
            definitionFingerprint: resolvedFingerprint,
            capturedAt: .distantPast,
            itemCount: snapshotItems.count,
            relevanceRoots: scopes,
        ),
        appVersion: nil,
    )
}

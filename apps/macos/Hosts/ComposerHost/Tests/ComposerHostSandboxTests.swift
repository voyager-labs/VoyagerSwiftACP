@testable import ComposerHost
import VoyagerShared
import XCTest

@MainActor
final class ComposerHostSandboxTests: XCTestCase {
    func testRegistryCoversRequiredPropertyAndOperatorContracts() throws {
        let registry = ComposerHostSandbox.makeRegistryClient()

        XCTAssertTrue(ComposerHostSandbox.registryCoverageIsComplete())
        XCTAssertEqual(registry.propertyTypeString(for: "kind"), "categorical")
        XCTAssertNotNil(registry.unitSpec(for: "file_size"))

        let dateRange = try registry.resolveCondition(
            propertyKey: "modified_date",
            operatorCode: "btw",
            values: ["2025-01-01", "2025-01-31"],
            sourcePayload: nil,
        )
        XCTAssertTrue(dateRange.isExecutionReady)
        XCTAssertEqual(dateRange.operation?.valueContract.input, .rangeDate)
    }

    func testSearchFixtureIsDeterministicAndEchoesAppliedFilters() async throws {
        let corpus = try ComposerHostFixtureTestResources.corpus()
        let root = URL(fileURLWithPath: corpus.rootPath)
        let filters = SearchFiltersPayload(
            scopes: [root.appendingPathComponent("documents").path],
            conditions: [.init(propertyKey: "kind", operator: "eq", value: .string("PDF"))],
            excludedScopes: [root.appendingPathComponent("documents/hwp").path],
            includeSubfolders: true,
        )
        let searchClient = ComposerHostSandbox.makeSearchClient(corpus: corpus)

        let first = try await searchClient.search(.init(query: "", filters: filters))
        let second = try await searchClient.search(.init(query: "", filters: filters))
        let applied = try await searchClient.applyFilters(.init(filters: filters))
        let expectedPaths = ComposerHostFixtureEvaluator.evaluate(
            corpus: corpus,
            query: "",
            filters: filters,
            policy: .init(),
        )
        .map(\.absolutePath)

        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.itemCount, 0)
        XCTAssertEqual(first.itemCount, first.items?.count)
        XCTAssertEqual(applied.itemCount, applied.items?.count)
        XCTAssertEqual(first.items, applied.items)
        let responseItems = try XCTUnwrap(first.items)
        let responsePaths = responseItems.compactMap { item -> String? in
            guard case let .string(path) = item else { return nil }
            return path
        }
        XCTAssertEqual(responsePaths.count, responseItems.count)
        XCTAssertEqual(responsePaths, expectedPaths)
        XCTAssertTrue(responsePaths.allSatisfy { path in
            path == (path as NSString).standardizingPath && corpus.entriesByAbsolutePath[path] != nil
        })
        XCTAssertEqual(first.appliedFilters?.scopes, filters.scopes)
        XCTAssertEqual(first.appliedFilters?.excludedScopes, filters.excludedScopes)
        XCTAssertEqual(first.appliedFilters?.conditions, filters.conditions)
    }

    func testScopeAndTagFixturesContainOnlyFixedValues() throws {
        let entryLoadingClient = ComposerHostSandbox.makeEntryLoadingClient()
        let favorites = ComposerHostSandbox.favorites
        let tags = ComposerHostSandbox.makeFinderFavoritesTagClient().favoriteTags()

        XCTAssertEqual(favorites.map(\.url.path), [
            ComposerHostSandbox.documentsPath,
            ComposerHostSandbox.projectsPath,
            ComposerHostSandbox.downloadsPath,
        ])
        XCTAssertEqual(ComposerHostSandbox.historyPaths, [
            ComposerHostSandbox.projectsPath,
            ComposerHostSandbox.downloadsPath,
        ])
        XCTAssertTrue(entryLoadingClient.fileExists(ComposerHostSandbox.documentsPath))
        XCTAssertEqual(
            try entryLoadingClient.contentsOfDirectory(
                URL(fileURLWithPath: ComposerHostSandbox.projectsPath),
                [],
                [],
            ).map(\.path),
            ["/Fixture/Projects/Composer"],
        )
        XCTAssertEqual(tags.map(\.name), ["Work", "Pinned", "Archive"])
    }

    func testSmokeContractValidatesAllPresetsAndConstruction() throws {
        let corpus = try ComposerHostFixtureTestResources.corpus()
        let collections = try ComposerHostFixtureTestResources.collections()

        XCTAssertGreaterThan(corpus.entries.count, 0)
        XCTAssertEqual(collections.count, 14)
        for preset in ComposerHostPreset.allCases {
            let store = ComposerHostStoreContainer.makeStore(preset: preset, corpus: corpus)

            XCTAssertNotNil(Optional(store), preset.rawValue)
        }
    }
}

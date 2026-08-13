import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class FilterSearchQueryBuilderTests: XCTestCase {
    /// RCL-003-apply_deterministic_filters: 저장된 collection fixture로 실제 파일 검색 결과를 복원한다.
    /// `.voycoll`의 load/save/reload와 condition resolution을 거쳐 production Spotlight service를 실행한다.
    /// - 검증 내용: collection identity, persisted condition, applied filters, exact fixture paths
    /// - 사전 조건: legacy kind/size collection과 Spotlight에 색인된 PDF repository fixture가 존재함
    /// - 기대 결과: 조건을 충족하는 PDF fixture 8개가 정확히 반환되고 원본 collection은 변경되지 않음
    func testSavedCollectionFixtureReturnsExactIndexedPDFPaths() async throws {
        let fixture = try SavedCollectionSearchFixture.make(sourceFilePath: #filePath)
        defer { try? fixture.cleanup() }

        let opened = try await CollectionFileClient.liveValue.load(fixture.collectionFixture)
        let remapped = opened.file.replacingScopes([fixture.corpus.path])
        try await CollectionFileClient.liveValue.save(remapped, fixture.savedCollection)
        let reloaded = try await CollectionFileClient.liveValue.load(fixture.savedCollection)

        let resolved = reloaded.file.resolveCollectionFilters(registryClient: RegistryClient.liveValue)
        let conditions = resolved.conditions.compactMap { condition -> SearchConditionPayload? in
            guard let operation = condition.operation,
                  let value = ConditionCodec.encode(condition: condition)
            else {
                return nil
            }
            return SearchConditionPayload(
                propertyKey: condition.property.key,
                operator: operation.code,
                value: value,
            )
        }
        let filters = SearchFiltersPayload(
            scopes: resolved.scopes,
            conditions: conditions,
            excludedScopes: resolved.excludedScopes,
            includeSubfolders: reloaded.file.includeSubfolders,
        )
        let response = try await SpotlightSearchService().applyFilters(filters)

        XCTAssertEqual(opened.file.id, "rcl-condition-collection")
        XCTAssertEqual(reloaded.file.conditions, opened.file.conditions)
        XCTAssertEqual(filters.conditions.map(\.propertyKey), ["file_kind", "size"])
        XCTAssertNil(response.error)
        XCTAssertEqual(response.appliedFilters?.scopes, [fixture.corpus.path])
        XCTAssertEqual(response.itemCount, fixture.expectedPaths.count)
        XCTAssertEqual(try XCTUnwrap(response.items).compactMap(searchResultPath).sorted(), fixture.expectedPaths)
    }

    func testScopeNormalizerNormalizesAndDedupesIdenticalScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "  /Users/test/Downloads/  ",
            "/Users/test/Downloads/subfolder",
            "/Users/test/Downloads",
            "",
        ])

        XCTAssertEqual(normalized, ["/Users/test/Downloads", "/Users/test/Downloads/subfolder"])
    }

    func testScopeNormalizerPreservesRootAndExplicitSubScopes() {
        let normalized = SearchScopeNormalizer.normalizeScopes([
            "/Users/test",
            "/",
            "/Users/test/Downloads",
        ])

        XCTAssertEqual(normalized, ["/Users/test", "/", "/Users/test/Downloads"])
    }

    func testScopeNormalizerExpandsTildeAndPreservesHomeSubScopes() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        let normalized = SearchScopeNormalizer.normalizeScopes([
            "~/Documents",
            homePath + "/Documents/subfolder",
        ])

        XCTAssertEqual(normalized, [homePath + "/Documents", homePath + "/Documents/subfolder"])
    }

    func testScopeNormalizerReturnsEmptyWhenScopesAreBlank() {
        XCTAssertEqual(SearchScopeNormalizer.normalizeScopes(["", "   "]), [])
    }

    func testConditionCompilerEqOnNameStemIncludesBareAndExtensionForms() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "name_stem",
            operator: "eq",
            value: .string("report"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report\""))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"report.*\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerRangeOnSizeBuildsInclusiveBounds() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "size",
            operator: "btw",
            value: .array([.number(100), .number(200)]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize >= 100"))
        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize <= 200"))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerEqAndNeqOnExtensionUsePathExtension() throws {
        let compiler = try makeCompiler()
        let homeURL = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        for operatorCode in ["eq", "neq"] {
            let condition = SearchConditionPayload(
                propertyKey: "extension",
                operator: operatorCode,
                value: .string("pdf"),
            )
            let plan = try compiler.compilePlan(conditions: [condition])

            XCTAssertEqual(plan.predicate, SpotlightQueryCompiler.basePredicate)
            XCTAssertEqual(plan.pathConditions, [condition])
            XCTAssertEqual(
                HistoricalPathConditionEvaluator.matches(
                    "/Users/test/Documents/report.pdf",
                    conditions: plan.pathConditions,
                    homeURL: homeURL,
                ),
                operatorCode == "eq",
            )
        }
    }

    func testConditionCompilerRestoresHistoricalNotEmptyAsExists() throws {
        let compiler = try makeCompiler()
        let plan = try compiler.compilePlan(conditions: [
            .init(propertyKey: "size", operator: "not_empty", value: nil),
        ])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSSize != nil"), plan.predicate)
    }

    func testConditionCompilerRestoresHistoricalOperatorProfiles() throws {
        let compiler = try makeCompiler()
        let cases: [(SearchConditionPayload, [String])] = [
            (
                .init(
                    propertyKey: "file_kind",
                    operator: "all",
                    value: .array([.string("PDF"), .string("Document")]),
                ),
                ["kMDItemKind == \"*PDF*\"", "kMDItemKind == \"*Document*\"", " && "],
            ),
            (
                .init(propertyKey: "tag_names", operator: "cn", value: .string("work")),
                ["kMDItemUserTags == \"*work*\""],
            ),
            (
                .init(propertyKey: "is_invisible", operator: "neq", value: .bool(true)),
                ["kMDItemFSInvisible != TRUE"],
            ),
            (
                .init(
                    propertyKey: "audio_channel_count",
                    operator: "in",
                    value: .array([.number(1), .number(2)]),
                ),
                ["kMDItemAudioChannelCount == 1", "kMDItemAudioChannelCount == 2", " || "],
            ),
            (
                .init(
                    propertyKey: "extension",
                    operator: "in",
                    value: .array([.string("pdf"), .string("md")]),
                ),
                ["kMDItemFSName == \"*.pdf\"", "kMDItemFSName == \"*.md\"", " || "],
            ),
            (
                .init(
                    propertyKey: "uniform_type_identifier",
                    operator: "in",
                    value: .array([.string("public.pdf")]),
                ),
                ["kMDItemContentType == \"public.pdf\""],
            ),
        ]

        for (condition, fragments) in cases {
            let plan = try compiler.compilePlan(conditions: [condition])
            for fragment in fragments {
                XCTAssertTrue(plan.predicate.contains(fragment), plan.predicate)
            }
        }
    }

    func testConditionCompilerEvaluatesHistoricalScalarExtensionAgainstPathExtension() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "contains",
            value: .string("pdf"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.predicate, SpotlightQueryCompiler.basePredicate)
        XCTAssertEqual(
            plan.pathConditions,
            [.init(propertyKey: "extension", operator: "cn", value: .string("pdf"))],
        )
        XCTAssertTrue(HistoricalPathConditionEvaluator.matches(
            "/Users/test/Documents/report.pdf",
            conditions: plan.pathConditions,
            homeURL: URL(fileURLWithPath: "/Users/test", isDirectory: true),
        ))
        XCTAssertFalse(HistoricalPathConditionEvaluator.matches(
            "/Users/test/Documents/pdf_notes.txt",
            conditions: plan.pathConditions,
            homeURL: URL(fileURLWithPath: "/Users/test", isDirectory: true),
        ))
    }

    func testConditionCompilerAnyOnExtensionUsesMditemAttribute() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "any",
            value: .array([.string("pdf")]),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"*.pdf\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
    }

    func testConditionCompilerPreservesHistoricalColorSpaceInAsExactMembership() throws {
        let compiler = try makeCompiler()
        let plan = try compiler.compilePlan(conditions: [
            .init(
                propertyKey: "color_space",
                operator: "in",
                value: .array([.string("RGB"), .string("CMYK")]),
            ),
        ])

        XCTAssertTrue(plan.predicate.contains("kMDItemColorSpace == \"RGB\""), plan.predicate)
        XCTAssertTrue(plan.predicate.contains("kMDItemColorSpace == \"CMYK\""), plan.predicate)
        XCTAssertFalse(plan.predicate.contains("*RGB*"), plan.predicate)
        XCTAssertFalse(plan.predicate.contains("*CMYK*"), plan.predicate)
    }

    /// RCL-003-apply_deterministic_filters: historical string none/miss 조건을 컴파일함
    /// 과거 alpha-list 부정 연산자가 단일 문자열 decoder로 빠지지 않고 list clause를 생성하는지 검증한다.
    /// - 검증 내용: not_contains_any/not_contains_all의 none/miss 정규화와 부정 predicate
    /// - 사전 조건: file_kind와 extension에 배열 값이 저장된 historical payload
    /// - 기대 결과: 모든 값을 부정하는 none/miss predicate가 오류 없이 생성됨
    func testConditionCompilerRestoresHistoricalNegativeStringListOperators() throws {
        let compiler = try makeCompiler()
        let cases: [(SearchConditionPayload, [String])] = [
            (
                .init(
                    propertyKey: "file_kind",
                    operator: "miss",
                    value: .array([.string("PDF"), .string("Document")]),
                ),
                ["!(kMDItemKind == \"*PDF*\")", "!(kMDItemKind == \"*Document*\")", " || "],
            ),
            (
                .init(
                    propertyKey: "file_kind",
                    operator: "not_contains_any",
                    value: .array([.string("PDF"), .string("Document")]),
                ),
                ["!(kMDItemKind == \"*PDF*\")", "!(kMDItemKind == \"*Document*\")", " && "],
            ),
            (
                .init(
                    propertyKey: "extension",
                    operator: "not_contains_all",
                    value: .array([.string("pdf"), .string("md")]),
                ),
                ["!(kMDItemFSName == \"*.pdf\")", "!(kMDItemFSName == \"*.md\")", " || "],
            ),
        ]

        for (condition, fragments) in cases {
            let plan = try compiler.compilePlan(conditions: [condition])
            for fragment in fragments {
                XCTAssertTrue(plan.predicate.contains(fragment), plan.predicate)
            }
        }
    }

    func testConditionCompilerSeparatesRetiredPathConditionsFromSpotlightPushdown() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "relative_path_from_home",
            operator: "starts_with",
            value: .string("~/Documents"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertEqual(plan.predicate, SpotlightQueryCompiler.basePredicate)
        XCTAssertEqual(plan.pushdownConditions, [])
        XCTAssertEqual(plan.pathConditions, [
            .init(propertyKey: "relative_path_from_home", operator: "sw", value: .string("~/Documents")),
        ])
    }

    func testHistoricalPathConditionEvaluatorMatchesIndexedPathFields() {
        let homeURL = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let path = "/Users/test/Documents/report.pdf"
        let conditions: [SearchConditionPayload] = [
            .init(propertyKey: "dir_path", operator: "eq", value: .string("/Users/test/Documents")),
            .init(propertyKey: "parent_dir_name", operator: "eq", value: .string("Documents")),
            .init(propertyKey: "depth_from_home", operator: "eq", value: .number(1)),
            .init(propertyKey: "relative_path_from_home", operator: "sw", value: .string("~/Documents")),
            .init(propertyKey: "dir_path", operator: "rx", value: .string("/Users/test/Doc.*")),
        ]

        XCTAssertTrue(HistoricalPathConditionEvaluator.matches(path, conditions: conditions, homeURL: homeURL))
        XCTAssertFalse(HistoricalPathConditionEvaluator.matches(
            "/Users/test/Downloads/report.pdf",
            conditions: conditions,
            homeURL: homeURL,
        ))
    }

    /// RCL-003-apply_deterministic_filters: path-derived 숫자 조건의 존재 여부를 평가함
    /// 값이 없는 depth_from_home exists/empty 조건을 숫자 비교 전에 처리하는지 검증한다.
    /// - 검증 내용: numeric path candidate의 exists/empty no-value operator
    /// - 사전 조건: 홈 하위 파일에 depth_from_home path condition이 적용됨
    /// - 기대 결과: exists는 true이고 empty는 false임
    func testHistoricalPathConditionEvaluatorHandlesNumericExistsAndEmpty() {
        let homeURL = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let path = "/Users/test/Documents/report.pdf"
        let outsideHomePath = "/Volumes/External/report.pdf"

        XCTAssertTrue(HistoricalPathConditionEvaluator.matches(
            path,
            conditions: [.init(propertyKey: "depth_from_home", operator: "exists", value: nil)],
            homeURL: homeURL,
        ))
        XCTAssertFalse(HistoricalPathConditionEvaluator.matches(
            path,
            conditions: [.init(propertyKey: "depth_from_home", operator: "empty", value: nil)],
            homeURL: homeURL,
        ))
        XCTAssertFalse(HistoricalPathConditionEvaluator.matches(
            outsideHomePath,
            conditions: [.init(propertyKey: "depth_from_home", operator: "exists", value: nil)],
            homeURL: homeURL,
        ))
        XCTAssertTrue(HistoricalPathConditionEvaluator.matches(
            outsideHomePath,
            conditions: [.init(propertyKey: "depth_from_home", operator: "empty", value: nil)],
            homeURL: homeURL,
        ))
        XCTAssertFalse(HistoricalPathConditionEvaluator.matches(
            outsideHomePath,
            conditions: [.init(propertyKey: "depth_from_home", operator: "lt", value: .number(0))],
            homeURL: homeURL,
        ))
    }
}

private struct SavedCollectionSearchFixture {
    let root: URL
    let collectionFixture: URL
    let savedCollection: URL
    let corpus: URL
    let expectedPaths: [String]

    static func make(sourceFilePath: String) throws -> Self {
        let repositoryRoot = try findRepositoryRoot(sourceFilePath: sourceFilePath)
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("VoyagerSavedCollectionSearch-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let corpus = repositoryRoot.appendingPathComponent("fixtures/fixtures/documents/pdf", isDirectory: true)
        let expectedPaths = try fileManager.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map(\.standardizedFileURL.path)
            .sorted()

        return Self(
            root: root,
            collectionFixture: repositoryRoot
                .appendingPathComponent("fixtures/fixtures/collections/condition_collection.voycoll"),
            savedCollection: root.appendingPathComponent("reloaded.voycoll"),
            corpus: corpus,
            expectedPaths: expectedPaths,
        )
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: root)
    }

    private static func findRepositoryRoot(sourceFilePath: String) throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path),
               fileManager.fileExists(atPath: directory.appendingPathComponent("fixtures/fixtures").path)
            {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                throw NSError(domain: "SavedCollectionSearchFixture", code: 1)
            }
            directory = parent
        }
    }
}

private extension VoyagerCollectionFile {
    func replacingScopes(_ scopes: [String]) -> Self {
        Self(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            query: query,
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            includeDirectories: includeDirectories,
            conditions: conditions,
            snapshot: snapshot,
            snapshotMeta: snapshotMeta,
            appVersion: appVersion,
        )
    }
}

private func searchResultPath(_ item: JSONValue) -> String? {
    guard case let .string(path) = item else { return nil }
    return URL(fileURLWithPath: path).standardizedFileURL.path
}

private extension FilterSearchQueryBuilderTests {
    func makeCompiler() throws -> SpotlightQueryCompiler {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }

    func loadRegistry<T: Decodable>(fileName: String) throws -> T {
        try RepositorySharedFixture.decode(fileName: fileName, sourceFilePath: #filePath)
    }
}

@testable import ComposerHost
import Foundation
import VoyagerShared
import XCTest

@MainActor
final class ComposerHostFixtureTests: XCTestCase {
    func testFixtureRootResolvesFromExplicitProjectRoot() throws {
        let root = try ComposerHostFixtureTestResources.root()

        XCTAssertTrue(root.path.hasSuffix("fixtures/fixtures"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("collections").path))
    }

    func testFixtureRootRejectsAnExplicitMissingProjectRoot() {
        let missingProjectRoot = "/ComposerHostFixtureTests-missing-project-root"

        XCTAssertThrowsError(try ComposerHostFixtureRootResolver.resolve(
            environment: ["VOYAGER_PROJECT_ROOT": missingProjectRoot],
            currentDirectoryPath: missingProjectRoot,
        )) { error in
            XCTAssertEqual(
                error as? ComposerHostFixtureError,
                .invalidRoot("\(missingProjectRoot)/fixtures/fixtures"),
            )
        }
    }

    func testCorpusEnumeratesSearchableFixturePayloadWithStableMetadata() throws {
        let corpus = try ComposerHostFixtureTestResources.corpus()
        let paths = corpus.entries.map(\.relativePath)

        XCTAssertGreaterThan(corpus.entries.count, 1900)
        XCTAssertEqual(paths, paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(corpus.entries.allSatisfy { entry in
            entry.absolutePath.hasPrefix(corpus.rootPath + "/")
                && !entry.relativePath.hasPrefix("collections/")
                && !entry.name.isEmpty
                && !entry.kind.isEmpty
                && entry.stableDate.timeIntervalSince1970 > 0
                && entry.tags == entry.tags.sorted()
        })
    }

    func testCorpusExcludesCollectionsAndAppliesDirectoryPolicy() throws {
        let corpus = try ComposerHostFixtureTestResources.corpus()
        let ordinaryDirectory = try XCTUnwrap(corpus.entries.first(where: { $0.isDirectory && !$0.isPackage }))
        let entries = ComposerHostFixtureEvaluator.evaluate(
            corpus: corpus,
            query: "",
            filters: emptyFilters,
            policy: .init(includeDirectories: false),
        )

        XCTAssertFalse(corpus.entries.contains { $0.relativePath.hasPrefix("collections/") })
        XCTAssertFalse(entries.contains(ordinaryDirectory))
    }

    func testCorpusLoaderEmitsPackageWithoutItsChildAndEvaluatorKeepsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComposerHostFixtureTests-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("Sample.voycoll", isDirectory: true)
        let child = package.appendingPathComponent("payload.json")
        let payload = Data("fixture payload".utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("collections", isDirectory: true),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try payload.write(to: child)

        let corpus = try ComposerHostFixtureCorpusLoader.load(root: root)
        let entries = ComposerHostFixtureEvaluator.evaluate(
            corpus: corpus,
            query: "",
            filters: emptyFilters,
            policy: .init(includeDirectories: false),
        )
        let loadedPackage = try XCTUnwrap(corpus.entries.first { $0.relativePath == "Sample.voycoll" })

        XCTAssertEqual(corpus.entries.count, 1)
        XCTAssertEqual(loadedPackage.entryType, .package)
        XCTAssertEqual(loadedPackage.size, Int64(payload.count))
        XCTAssertFalse(corpus.entries.contains { $0.relativePath == "Sample.voycoll/payload.json" })
        XCTAssertEqual(entries, [loadedPackage])
    }

    func testEvaluatorCoversQueriesScopesAndAllSupportedConditionFamilies() {
        let corpus = syntheticCorpus

        assertQueryAndScopeEvaluation(corpus)
        assertTextAndSizeConditionEvaluation(corpus)
        assertDateTagAndHiddenConditionEvaluation(corpus)
    }

    func testEvaluatorPreservesNumericRangeArrayValues() {
        XCTAssertEqual(
            evaluate(
                syntheticCorpus,
                filters: filters("file_size", "between", .array([.number(1000), .number(2000)])),
            ),
            ["documents/Example.pages", "documents/Quarterly Report.pdf"],
        )
    }

    func testEvaluatorMatchesRegistryOperatorSemantics() {
        assertRegistryStringOperators()
        assertRegistryNumberOperators()
        assertRegistryDateOperators()
        assertRegistryListAndBooleanOperators()
    }
}

extension ComposerHostFixtureTests {
    private func assertRegistryStringOperators() {
        assertRegistryMatch("name_stem", "cn", .string("voyager"), ["documents/Voyager Plan.md"])
        assertRegistryMatch("name_stem", "nc", .string("report"), [
            ".hidden/Secret.txt", "documents/Example.pages", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("extension", "sw", .string("p"), [
            "documents/Example.pages", "documents/Quarterly Report.pdf",
        ])
        assertRegistryMatch("extension", "ew", .string("f"), ["documents/Quarterly Report.pdf"])
        assertRegistryMatch("name_stem", "neq", .string("Secret"), [
            "documents/Example.pages", "documents/Quarterly Report.pdf", "documents/Voyager Plan.md",
        ])
    }

    private func assertRegistryNumberOperators() {
        assertRegistryMatch("file_size", "lt", .number(1000), [
            ".hidden/Secret.txt", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("file_size", "gte", .number(1500), [
            "documents/Example.pages", "documents/Quarterly Report.pdf",
        ])
        assertRegistryMatch("file_size", "lte", .number(512), [
            ".hidden/Secret.txt", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("file_size", "neq", .number(1500), [
            ".hidden/Secret.txt", "documents/Example.pages", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("file_size", "nbtw", .array([.number(500), .number(1600)]), [
            ".hidden/Secret.txt", "documents/Example.pages",
        ])
    }

    private func assertRegistryDateOperators() {
        assertRegistryMatch("modified_date", "today", nil, [
            ".hidden/Secret.txt", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("modified_date", "lt", .string("2025-01-03"), [
            ".hidden/Secret.txt", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("modified_date", "gte", .string("2025-01-03"), [
            "documents/Example.pages", "documents/Quarterly Report.pdf",
        ])
        assertRegistryMatch("modified_date", "lte", .string("2025-01-01"), [
            ".hidden/Secret.txt", "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("modified_date", "neq", .string("2025-01-01"), [
            "documents/Example.pages", "documents/Quarterly Report.pdf",
        ])
        assertRegistryMatch(
            "modified_date",
            "nbtw",
            .array([.string("2025-01-01"), .string("2025-01-01")]),
            ["documents/Example.pages", "documents/Quarterly Report.pdf"],
        )
    }

    private func assertRegistryListAndBooleanOperators() {
        assertRegistryMatch("tag_names", "none", .array([.string("Documents")]), [".hidden/Secret.txt"])
        assertRegistryMatch("tag_names", "all", .array([.string("Documents"), .string("Work")]), [
            "documents/Voyager Plan.md",
        ])
        assertRegistryMatch("tag_names", "miss", .array([.string("Documents")]), [".hidden/Secret.txt"])
        assertRegistryMatch("is_hidden", "neq", .bool(true), [
            "documents/Example.pages", "documents/Quarterly Report.pdf", "documents/Voyager Plan.md",
        ])
    }

    private func assertRegistryMatch(
        _ propertyKey: String,
        _ operation: String,
        _ value: JSONValue?,
        _ expected: [String],
    ) {
        XCTAssertEqual(
            evaluate(syntheticCorpus, filters: filters(propertyKey, operation, value)),
            expected,
            "\(propertyKey) \(operation)",
        )
    }

    private func assertQueryAndScopeEvaluation(_ corpus: ComposerHostFixtureCorpus) {
        XCTAssertEqual(evaluate(corpus, query: "voyager"), ["documents/Voyager Plan.md"])
        XCTAssertEqual(
            evaluate(corpus, filters: .init(
                scopes: ["/Fixture/documents"],
                conditions: [],
                excludedScopes: ["/Fixture/documents/private"],
                includeSubfolders: true,
            )),
            ["documents/Example.pages", "documents/Quarterly Report.pdf", "documents/Voyager Plan.md"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: .init(
                scopes: ["/Fixture/documents/Voyager Plan.md"],
                conditions: [],
            )),
            ["documents/Voyager Plan.md"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: .init(
                scopes: ["/Fixture/documents"],
                conditions: [],
                excludedScopes: ["/Fixture/documents/Voyager Plan.md"],
                includeSubfolders: false,
            )),
            ["documents/Example.pages", "documents/Quarterly Report.pdf", "documents/Voyager Plan.md"],
        )
    }

    func testConditionNormalizationPreservesScalarJSONTypes() {
        let number = ComposerHostFixtureConditionNormalization.normalized(.init(
            propertyKey: "size",
            operatorCode: "greaterThan",
            value: .number(1024),
        ))
        let toggle = ComposerHostFixtureConditionNormalization.normalized(.init(
            propertyKey: "hidden",
            operatorCode: "equals",
            value: .bool(true),
        ))
        let list = ComposerHostFixtureConditionNormalization.normalized(.init(
            propertyKey: "extension",
            operatorCode: "in",
            value: .string("pdf, txt"),
        ))
        let numericListScalar = ComposerHostFixtureConditionNormalization.normalized(.init(
            propertyKey: "size",
            operatorCode: "in",
            value: .number(1024),
        ))
        let booleanListScalar = ComposerHostFixtureConditionNormalization.normalized(.init(
            propertyKey: "hidden",
            operatorCode: "any",
            value: .bool(true),
        ))

        XCTAssertEqual(number.value, .number(1024))
        XCTAssertEqual(toggle.value, .bool(true))
        XCTAssertEqual(list.value, .array([.string("pdf"), .string("txt")]))
        XCTAssertEqual(numericListScalar.value, .number(1024))
        XCTAssertEqual(booleanListScalar.value, .bool(true))
    }

    private func assertTextAndSizeConditionEvaluation(_ corpus: ComposerHostFixtureCorpus) {
        XCTAssertEqual(
            evaluate(corpus, filters: filters("name", "contains", .string("voyager"))),
            ["documents/Voyager Plan.md"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("name_stem", "eq", .string("Quarterly Report"))),
            ["documents/Quarterly Report.pdf"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("extension", "in", .string("txt, PDF"))),
            [".hidden/Secret.txt", "documents/Quarterly Report.pdf"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("kind", "equals", .string("pdf"))),
            ["documents/Quarterly Report.pdf"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("size", "greaterThan", .string("1000"))),
            ["documents/Example.pages", "documents/Quarterly Report.pdf"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("file_size", "between", .array([.string("1000"), .string("2000")]))),
            ["documents/Example.pages", "documents/Quarterly Report.pdf"],
        )
    }

    private func assertDateTagAndHiddenConditionEvaluation(_ corpus: ComposerHostFixtureCorpus) {
        XCTAssertEqual(
            evaluate(corpus, filters: filters("modifiedDate", "before", .string("2025-01-02"))),
            [".hidden/Secret.txt", "documents/Voyager Plan.md"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("created", "after", .string("2025-01-02"))),
            ["documents/Example.pages", "documents/Quarterly Report.pdf"],
        )
        XCTAssertEqual(
            evaluate(
                corpus,
                filters: filters("modified_date", "btw", .array([.string("2025-01-01"), .string("2025-01-03")])),
            ),
            [
                ".hidden/Secret.txt",
                "documents/Example.pages",
                "documents/Quarterly Report.pdf",
                "documents/Voyager Plan.md",
            ],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("tag", "any", .array([.string("archive"), .string("work")]))),
            ["documents/Quarterly Report.pdf", "documents/Voyager Plan.md"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("tag_names", "exists", nil)),
            [
                ".hidden/Secret.txt",
                "documents/Example.pages",
                "documents/Quarterly Report.pdf",
                "documents/Voyager Plan.md",
            ],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("hidden", "eq", .bool(true))),
            [".hidden/Secret.txt"],
        )
        XCTAssertEqual(
            evaluate(corpus, filters: filters("is_hidden", "eq", .bool(false))),
            ["documents/Example.pages", "documents/Quarterly Report.pdf", "documents/Voyager Plan.md"],
        )
    }

    func testEvaluatorIsDeterministicAndIncludesPackagesWhenDirectoriesAreExcluded() {
        let filters = emptyFilters
        let first = ComposerHostFixtureEvaluator.evaluate(
            corpus: syntheticCorpus,
            query: "",
            filters: filters,
            policy: .init(includeDirectories: false),
        )
        let second = ComposerHostFixtureEvaluator.evaluate(
            corpus: syntheticCorpus,
            query: "",
            filters: filters,
            policy: .init(includeDirectories: false),
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.map(\.relativePath),
            [
                ".hidden/Secret.txt",
                "documents/Example.pages",
                "documents/Quarterly Report.pdf",
                "documents/Voyager Plan.md",
            ],
        )
    }

    func testCollectionCatalogDiscoversAllDefinitionsAndRestoresCurrentAndLegacyDefinitions() async throws {
        let root = try ComposerHostFixtureTestResources.root()
        let definitions = try ComposerHostFixtureTestResources.collections()
        let registry = ComposerHostSandbox.makeRegistryClient()
        let current = try definition(named: "basic_collection", from: definitions)
        let legacy = try definition(named: "legacy_schema_v1_collection", from: definitions)
        let currentDraft = try await ComposerHostCollectionCatalog.load(
            definition: current,
            fixtureRoot: root,
            registryClient: registry,
        )
        let legacyDraft = try await ComposerHostCollectionCatalog.load(
            definition: legacy,
            fixtureRoot: root,
            registryClient: registry,
        )

        XCTAssertEqual(definitions.count, 14)
        XCTAssertTrue(definitions.contains { $0.isPackage })
        XCTAssertEqual(currentDraft.payload.context.query, "quarterly report")
        XCTAssertEqual(currentDraft.payload.context.scopes, [root.path])
        XCTAssertTrue(currentDraft.payload.context.conditions.isEmpty)
        XCTAssertEqual(currentDraft.searchPolicy.includeDirectories, currentDraft.payload.context.includeDirectories)
        XCTAssertEqual(legacyDraft.payload.context.query, "legacy report")
        XCTAssertEqual(legacyDraft.payload.context.scopes, [root.path])
        XCTAssertEqual(legacyDraft.payload.context.conditions.count, 1)
        XCTAssertTrue(legacyDraft.diagnostics.isEmpty)
    }

    func testCollectionCatalogRestoresLegacyConditionFixtureWithoutDiagnostics() async throws {
        let root = try ComposerHostFixtureTestResources.root()
        let conditionCollection = try definition(
            named: "condition_collection",
            from: ComposerHostFixtureTestResources.collections(),
        )

        let draft = try await ComposerHostCollectionCatalog.load(
            definition: conditionCollection,
            fixtureRoot: root,
            registryClient: ComposerHostSandbox.makeRegistryClient(),
        )

        XCTAssertTrue(draft.diagnostics.isEmpty, draft.diagnostics.joined(separator: "\n"))
        XCTAssertFalse(draft.blocksExecution)
        XCTAssertEqual(draft.payload.context.excludedScopes, [root.appendingPathComponent("archives").path])
        XCTAssertEqual(draft.payload.context.conditions.map(\.property.key), ["file_kind", "size"])
        XCTAssertEqual(draft.payload.context.conditions.compactMap(\.operation?.code), ["any", "gt"])
        XCTAssertTrue(draft.payload.context.conditions.allSatisfy(\.isExecutionReady))
    }

    func testCollectionCatalogRemapsExclusionsAndCapturesDirectoryPolicy() async throws {
        let root = try ComposerHostFixtureTestResources.root()
        let definitions = try ComposerHostFixtureTestResources.collections()
        let registry = ComposerHostSandbox.makeRegistryClient()
        let scoped = try definition(named: "multi_scope_exclusion_collection", from: definitions)
        let directoryIncluding = try definition(named: "directory_including_collection", from: definitions)
        let scopedDraft = try await ComposerHostCollectionCatalog.load(
            definition: scoped,
            fixtureRoot: root,
            registryClient: registry,
        )
        let directoryDraft = try await ComposerHostCollectionCatalog.load(
            definition: directoryIncluding,
            fixtureRoot: root,
            registryClient: registry,
        )

        XCTAssertEqual(scopedDraft.payload.context.scopes, [root.path])
        XCTAssertEqual(scopedDraft.payload.context.excludedScopes, [root.appendingPathComponent("archives").path])
        XCTAssertTrue(scopedDraft.payload.context.includeSubfolders)
        XCTAssertEqual(scopedDraft.payload.context.conditions.map(\.property.key), ["name_stem", "file_kind"])
        XCTAssertEqual(scopedDraft.diagnostics.count, 1)
        XCTAssertTrue(scopedDraft.diagnostics.allSatisfy { $0.hasPrefix("Excluded scope does not exist: ") })
        XCTAssertTrue(scopedDraft.blocksExecution)
        XCTAssertTrue(directoryDraft.searchPolicy.includeDirectories)
        XCTAssertTrue(directoryDraft.payload.context.includeDirectories)
    }

    func testCollectionCatalogBlocksKnownConditionWithInvalidPersistedValue() async throws {
        let fixtureRoot = try ComposerHostFixtureTestResources.root()
        let source = fixtureRoot.appendingPathComponent("collections/condition_collection.voycoll", isDirectory: true)
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComposerHostFixtureTests-\(UUID().uuidString)", isDirectory: true)
        let copiedCollection = sandbox.appendingPathComponent("invalid_condition.voycoll", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: copiedCollection)
        let plistURL = copiedCollection.appendingPathComponent("collection.plist")
        let data = try Data(contentsOf: plistURL)
        var plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
        )
        var conditions = try XCTUnwrap(plist["conditions"] as? [[String: Any]])
        conditions[0]["value"] = []
        plist["conditions"] = conditions
        let invalidData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try invalidData.write(to: plistURL)

        let draft = try await ComposerHostCollectionCatalog.load(
            definition: .init(url: copiedCollection, name: "Invalid condition", isPackage: true),
            fixtureRoot: fixtureRoot,
            registryClient: ComposerHostSandbox.makeRegistryClient(),
        )

        XCTAssertTrue(draft.blocksExecution)
        XCTAssertTrue(draft.diagnostics.contains { $0.hasPrefix("Invalid condition: ") })
        XCTAssertFalse(try XCTUnwrap(draft.payload.context.conditions.first).isExecutionReady)
    }

    func testDiagnosticsBlockUnsupportedCollectionExecutionWithoutPartialSearch() async throws {
        let root = try ComposerHostFixtureTestResources.root()
        let definition = try definition(
            named: "basic_collection",
            from: ComposerHostFixtureTestResources.collections(),
        )
        let loaded = try await ComposerHostCollectionCatalog.load(
            definition: definition,
            fixtureRoot: root,
            registryClient: ComposerHostSandbox.makeRegistryClient(),
        )
        let unsupportedDefinition = ComposerHostCollectionDefinition(
            url: URL(fileURLWithPath: "/Fixture/unsupported.voycoll"),
            name: "Unsupported",
            isPackage: false,
        )
        let draft = ComposerHostRestoredCollectionDraft(
            definition: unsupportedDefinition,
            payload: loaded.payload,
            searchPolicy: .init(),
            diagnostics: ["Unsupported property: opaque"],
        )

        XCTAssertTrue(draft.blocksExecution)
        XCTAssertFalse(draft.diagnostics.isEmpty)
    }

    private func evaluate(
        _ corpus: ComposerHostFixtureCorpus,
        query: String = "",
        filters: SearchFiltersPayload = .init(
            scopes: [],
            conditions: [],
            excludedScopes: [],
            includeSubfolders: true,
        ),
    ) -> [String] {
        ComposerHostFixtureEvaluator.evaluate(
            corpus: corpus,
            query: query,
            filters: filters,
            policy: .init(includeDirectories: false),
        )
        .map(\.relativePath)
    }

    private func filters(_ propertyKey: String, _ operation: String, _ value: JSONValue?) -> SearchFiltersPayload {
        .init(
            scopes: [],
            conditions: [.init(propertyKey: propertyKey, operator: operation, value: value)],
            excludedScopes: [],
            includeSubfolders: true,
        )
    }

    private var emptyFilters: SearchFiltersPayload {
        .init(scopes: [], conditions: [], excludedScopes: [], includeSubfolders: true)
    }

    private func definition(
        named name: String,
        from definitions: [ComposerHostCollectionDefinition],
    ) throws -> ComposerHostCollectionDefinition {
        try XCTUnwrap(definitions.first { $0.name == name })
    }

    private var syntheticCorpus: ComposerHostFixtureCorpus {
        let january1 = Date(timeIntervalSince1970: 1_735_689_600)
        let january3 = Date(timeIntervalSince1970: 1_735_862_400)
        return .init(rootPath: "/Fixture", entries: [
            .init(
                absolutePath: "/Fixture/.hidden/Secret.txt",
                relativePath: ".hidden/Secret.txt",
                name: "Secret.txt",
                nameStem: "Secret",
                fileExtension: "txt",
                corpusCategory: ".hidden",
                entryType: .file,
                kind: "Text",
                size: 64,
                stableDate: january1,
                tags: ["Hidden"],
                isHidden: true,
                isDirectory: false,
                isPackage: false,
            ),
            .init(
                absolutePath: "/Fixture/documents/Voyager Plan.md",
                relativePath: "documents/Voyager Plan.md",
                name: "Voyager Plan.md",
                nameStem: "Voyager Plan",
                fileExtension: "md",
                corpusCategory: "documents",
                entryType: .file,
                kind: "Text",
                size: 512,
                stableDate: january1,
                tags: ["Documents", "Work"],
                isHidden: false,
                isDirectory: false,
                isPackage: false,
            ),
            .init(
                absolutePath: "/Fixture/documents/Quarterly Report.pdf",
                relativePath: "documents/Quarterly Report.pdf",
                name: "Quarterly Report.pdf",
                nameStem: "Quarterly Report",
                fileExtension: "pdf",
                corpusCategory: "documents",
                entryType: .file,
                kind: "PDF",
                size: 1500,
                stableDate: january3,
                tags: ["Archive", "Documents"],
                isHidden: false,
                isDirectory: false,
                isPackage: false,
            ),
            .init(
                absolutePath: "/Fixture/documents/Example.pages",
                relativePath: "documents/Example.pages",
                name: "Example.pages",
                nameStem: "Example",
                fileExtension: "pages",
                corpusCategory: "documents",
                entryType: .package,
                kind: "Documents Package",
                size: 2000,
                stableDate: january3,
                tags: ["Documents"],
                isHidden: false,
                isDirectory: true,
                isPackage: true,
            ),
            .init(
                absolutePath: "/Fixture/documents/private",
                relativePath: "documents/private",
                name: "private",
                nameStem: "private",
                fileExtension: "",
                corpusCategory: "documents",
                entryType: .directory,
                kind: "Folder",
                size: 0,
                stableDate: january1,
                tags: ["Documents"],
                isHidden: false,
                isDirectory: true,
                isPackage: false,
            ),
        ])
    }
}

enum ComposerHostFixtureTestResources {
    private static let rootResult: Result<URL, Error> = Result {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try ComposerHostFixtureRootResolver.resolve(
            environment: ["VOYAGER_PROJECT_ROOT": projectRoot.path],
            currentDirectoryPath: projectRoot.path,
        )
    }

    private static let corpusResult: Result<ComposerHostFixtureCorpus, Error> = Result {
        try ComposerHostFixtureCorpusLoader.load(root: root())
    }

    private static let collectionsResult: Result<[ComposerHostCollectionDefinition], Error> = Result {
        try ComposerHostCollectionCatalog.discover(root: root())
    }

    static func root() throws -> URL {
        try rootResult.get()
    }

    static func corpus() throws -> ComposerHostFixtureCorpus {
        try corpusResult.get()
    }

    static func collections() throws -> [ComposerHostCollectionDefinition] {
        try collectionsResult.get()
    }
}

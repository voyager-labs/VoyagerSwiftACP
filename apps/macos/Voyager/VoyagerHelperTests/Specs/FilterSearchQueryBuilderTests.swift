import Foundation
import VoyagerEntitiesAi
import VoyagerEntitiesCollection
@testable import VoyagerHelper
import VoyagerShared
import XCTest

@MainActor
final class FilterSearchQueryBuilderTests: XCTestCase {
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

    func testConditionCompilerEqOnExtensionUsesMditemAttribute() throws {
        let compiler = try makeCompiler()
        let condition = SearchConditionPayload(
            propertyKey: "extension",
            operator: "eq",
            value: .string("pdf"),
        )

        let plan = try compiler.compilePlan(conditions: [condition])

        XCTAssertTrue(plan.predicate.contains("kMDItemFSName == \"pdf\""))
        XCTAssertEqual(plan.pushdownConditions, [condition])
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
                ["kMDItemKind == \"PDF\"", "kMDItemKind == \"Document\"", " && "],
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
                ["!(kMDItemFSName == \"*pdf*\")", "!(kMDItemFSName == \"*md*\")", " || "],
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

private extension FilterSearchQueryBuilderTests {
    func makeCompiler() throws -> SpotlightQueryCompiler {
        let conditionRegistry: PropertyConditionRegistry =
            try loadRegistry(fileName: "property_condition_registry.json")
        let systemRegistry: SystemPropertyRegistry = try loadRegistry(fileName: "system_property_registry.json")
        let builder = SearchConditionBuilder(registry: conditionRegistry, systemRegistry: systemRegistry)
        return SpotlightQueryCompiler(conditionBuilder: builder)
    }

    func loadRegistry<T: Decodable>(fileName: String) throws -> T {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = rootURL.appendingPathComponent("shared").appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

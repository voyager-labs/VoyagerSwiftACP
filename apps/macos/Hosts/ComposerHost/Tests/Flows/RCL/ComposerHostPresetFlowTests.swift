@testable import ComposerHost
import XCTest

@MainActor
final class ComposerHostPresetFlowTests: XCTestCase {
    func testPresetsHaveUniqueStableScenarioIDs() {
        let presets = ComposerHostPreset.allCases

        XCTAssertEqual(Set(presets.map(\.rawValue)).count, presets.count)
        XCTAssertEqual(Set(presets.map(\.scenario.id)).count, presets.count)
        XCTAssertEqual(ComposerHostPreset.resolve("dateRange"), .dateRange)
        XCTAssertEqual(ComposerHostPreset.resolve("unknown"), .empty)
    }

    func testEveryPresetBuildsAnInteractiveCollectionState() throws {
        for preset in ComposerHostPreset.allCases {
            let state = try ComposerHostSandbox.makeInitialState(for: preset)

            XCTAssertTrue(state.isPresented, preset.rawValue)
            XCTAssertTrue(state.isCollectionMode, preset.rawValue)
            XCTAssertEqual(state.scopes, [ComposerHostSandbox.documentsPath], preset.rawValue)
        }
    }

    func testPresetsSelectExpectedConditionContracts() throws {
        let expected: [ComposerHostPreset: (String, String)] = [
            .textValue: ("name_stem", "eq"),
            .numberRange: ("size", "btw"),
            .boolean: ("is_invisible", "eq"),
            .tokenList: ("tag_names", "any"),
            .dateRange: ("modification_date", "btw"),
        ]

        for (preset, condition) in expected {
            let state = try ComposerHostSandbox.makeInitialState(for: preset)
            let editor = try XCTUnwrap(state.conditionEditors.first)

            XCTAssertEqual(editor.condition.property.key, condition.0)
            XCTAssertEqual(editor.condition.operation?.code, condition.1)
            XCTAssertTrue(editor.condition.isExecutionReady)
        }
    }
}

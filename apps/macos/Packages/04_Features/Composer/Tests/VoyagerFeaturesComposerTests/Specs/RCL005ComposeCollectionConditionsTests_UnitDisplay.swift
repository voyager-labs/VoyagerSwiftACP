import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class RCL005ComposeCollectionConditionsTestsUnitDisplay: XCTestCase {
    /// RCL-005-change_collection_condition_value: display unit은 UUID-owned editor presentation과 history에만 반영한다.
    /// unit 선택은 semantic Condition이나 다른 row를 변경하지 않고 undo 가능한 display state만 갱신하는지 검증한다.
    func testChangeConditionValue_setDisplayUnit_updatesOnlySelectedEditorAndHistory() async throws {
        let fixture = try makeFixture()
        let store = TestStore(initialState: fixture.state) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(
            id: fixture.firstID,
            action: .delegate(.setDisplayUnit("kilobyte")),
        )))

        XCTAssertEqual(
            store.state.conditionEditors[id: fixture.firstID]?.displayState?.unitValueState?.selectedUnitCode,
            "kilobyte",
        )
        XCTAssertEqual(
            store.state.conditionEditors[id: fixture.secondID]?.displayState?.unitValueState?.selectedUnitCode,
            "byte",
        )
        XCTAssertEqual(store.state.conditionEditors[id: fixture.firstID]?.condition, fixture.firstCondition)
        XCTAssertEqual(store.state.history.count, 1)
        XCTAssertEqual(
            store.state.history.last?.conditionEditors[id: fixture.firstID]?.displayState?.unitValueState?
                .selectedUnitCode,
            "byte",
        )
    }

    private func makeFixture() throws -> Fixture {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000007"))
        let unitContract = Condition.UnitContract(
            canonicalUnit: "byte",
            options: [
                .init(code: "byte", label: "Bytes", factorToCanonical: 1),
                .init(code: "kilobyte", label: "Kilobytes", factorToCanonical: 1000),
            ],
            defaultDisplayUnit: "byte",
        )
        let firstCondition = makeCondition(value: "1000", unitContract: unitContract)
        let secondCondition = makeCondition(value: "2000", unitContract: unitContract)
        var state = ComposerState()
        state.conditionEditors = [
            .init(
                id: firstID,
                condition: firstCondition,
                displayState: .init(values: ["1000"], unitValueState: .init(contract: unitContract)),
            ),
            .init(
                id: secondID,
                condition: secondCondition,
                displayState: .init(values: ["2000"], unitValueState: .init(contract: unitContract)),
            ),
        ]
        return .init(
            state: state,
            firstID: firstID,
            secondID: secondID,
            firstCondition: firstCondition,
        )
    }

    private func makeCondition(value: String, unitContract: Condition.UnitContract) -> Condition {
        Condition(
            property: .init(
                key: "file_size",
                label: "File Size",
                type: .number,
                unitContract: unitContract,
                operatorOptions: [.init(code: "eq", label: "Equals")],
            ),
            operation: .init(
                code: "eq",
                label: "Equals",
                valueContract: .init(shape: .single, count: .fixed(1), input: .singleNumber),
            ),
            values: [value],
            availability: .available,
            opaqueSource: nil,
        )
    }

    private struct Fixture {
        let state: ComposerState
        let firstID: UUID
        let secondID: UUID
        let firstCondition: Condition
    }
}

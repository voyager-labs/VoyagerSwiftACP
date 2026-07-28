import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class RCL005ComposeCollectionConditionsTestsUnitDisplay: XCTestCase {
    // MARK: - RCL-005-change_collection_condition_value

    /// RCL-005-change_collection_condition_value: 첫 단위 값 commit은 선택한 표시 단위를 보존한다.
    /// 단위 condition에 첫 값을 입력한 직후에도 사용자가 입력한 값과 단위가 그대로 표시되는지 검증한다.
    /// - 검증 내용: parent commit 후 canonical condition 값과 display values·selected unit 상태
    /// - 사전 조건: display state가 없는 file size condition에서 1 megabyte를 처음 commit함
    /// - 기대 결과: canonical 값 1048576과 display 값 1, megabyte 선택 상태가 함께 유지됨
    func testChangeConditionValue_firstUnitCommitPreservesSelectedDisplayUnit() async throws {
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000008"))
        let unitContract = Condition.UnitContract(
            canonicalUnit: "byte",
            options: [
                .init(code: "byte", label: "Bytes", factorToCanonical: 1),
                .init(code: "megabyte", label: "Megabytes", factorToCanonical: 1_048_576),
            ],
            defaultDisplayUnit: "byte",
        )
        let condition = makeCondition(value: nil, unitContract: unitContract)
        var state = ComposerState()
        state.conditionEditors = [.init(id: id, condition: condition)]
        let store = TestStore(initialState: state) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = .init(
                allProperties: { [] },
                labelForKey: { _ in "File Size" },
                propertyTypeString: { _ in "number" },
                propertyUnitSpec: { _ in nil },
                operatorCodes: { _ in ["eq"] },
                operatorDefinition: { _ in preconditionFailure("unused in this scenario") },
                resolvePropertyKey: { .canonical($0) },
                resolveCondition: { _, _, values, _ in
                    Condition(
                        property: condition.property,
                        operation: condition.operation,
                        values: values,
                        availability: .available,
                        opaqueSource: nil,
                    )
                },
            )
        }
        // history와 derived filter state 전체가 함께 바뀌므로 unit display 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(
            id: id,
            action: .delegate(.commitValues(
                values: ["1048576"],
                displayValues: ["1"],
                selectedUnitCode: "megabyte",
            )),
        )))

        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.values, ["1048576"])
        XCTAssertEqual(store.state.conditionEditors[id: id]?.displayState?.values, ["1"])
        XCTAssertEqual(
            store.state.conditionEditors[id: id]?.displayState?.unitValueState?.selectedUnitCode,
            "megabyte",
        )
    }

    /// RCL-005-change_collection_condition_value: display unit은 UUID-owned editor presentation과 history에만 반영한다.
    /// unit 선택은 semantic Condition이나 다른 row를 변경하지 않고 undo 가능한 display state만 갱신하는지 검증한다.
    func testChangeConditionValue_setDisplayUnit_updatesOnlySelectedEditorAndHistory() async throws {
        let fixture = try makeFixture()
        let store = TestStore(initialState: fixture.state) {
            ComposerFeature()
        }
        // history와 derived filter state 전체가 함께 바뀌므로 선택 editor의 display state만 검증한다.
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

    private func makeCondition(value: String?, unitContract: Condition.UnitContract) -> Condition {
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
            values: value.map { [$0] },
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

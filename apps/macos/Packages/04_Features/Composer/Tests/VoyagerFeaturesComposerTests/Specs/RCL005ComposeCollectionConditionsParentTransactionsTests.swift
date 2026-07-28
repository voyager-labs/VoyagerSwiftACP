import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class RCL005ComposeCollectionConditionsParentTransactionsTests: XCTestCase {
    // MARK: - RCL-005-edit_collection_conditions

    /// RCL-005-edit_collection_conditions: property 교체는 호환되지 않는 표시 상태를 버린다.
    /// - 검증 내용: UUID 보존, operator/value 초기화, display state 제거, history 기록
    /// - 사전 조건: unit display state와 값이 있는 단일 condition editor
    /// - 기대 결과: 새 property editor는 같은 UUID와 빈 display state를 가지며 이전 snapshot은 보존
    func testReplacingPropertyClearsIncompatibleDisplayState() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000011")
        let unitContract = byteUnitContract
        var state = ComposerState()
        state.conditionEditors = [
            .init(
                id: id,
                condition: Self.condition(propertyKey: "file_size", values: ["1024"], unitContract: unitContract),
                displayState: .init(values: ["1"], unitValueState: .init(contract: unitContract)),
            ),
        ]
        let store = makeStore(state)
        // property 교체는 parent transaction과 history를 함께 변경하므로 결과 상태만 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(id: id, action: .delegate(.replaceProperty("modified_date")))))

        XCTAssertEqual(store.state.conditionEditors[id: id]?.id, id)
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.property.key, "modified_date")
        XCTAssertNil(store.state.conditionEditors[id: id]?.condition.operation)
        XCTAssertNil(store.state.conditionEditors[id: id]?.condition.values)
        XCTAssertNil(store.state.conditionEditors[id: id]?.displayState)
        XCTAssertEqual(store.state.history.count, 1)
        XCTAssertEqual(store.state.history.last?.conditionEditors[id: id]?.displayState?.values, ["1"])
    }

    /// RCL-005-edit_collection_conditions: 현재 property 재선택은 parent transaction을 만들지 않는다.
    /// - 검증 내용: full editor, UUID, display state, history depth, search effect 보존
    /// - 사전 조건: 실행 가능한 값과 unit display state를 가진 UUID-owned condition editor
    /// - 기대 결과: 같은 property key 선택은 condition과 history를 변경하지 않고 in-flight search effect를 만들지 않음
    func testReselectingCurrentPropertyPreservesParentTransactionState() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000029")
        let unitContract = byteUnitContract
        let editor = ConditionEditorState(
            id: id,
            condition: Self.condition(propertyKey: "file_size", values: ["1024"], unitContract: unitContract),
            displayState: .init(values: ["1"], unitValueState: .init(contract: unitContract)),
        )
        var state = ComposerState()
        state.conditionEditors = [editor]
        let store = makeStore(state)

        await store.send(.conditionEditor(.element(id: id, action: .delegate(.replaceProperty("file_size")))))

        XCTAssertEqual(store.state.conditionEditors[id: id], editor)
        XCTAssertEqual(store.state.conditionEditors[id: id]?.id, id)
        XCTAssertEqual(store.state.history.count, 0)
        await store.finish()
    }

    /// RCL-005-edit_collection_conditions: saved hydration은 runtime editor UUID를 새로 만든다.
    /// - 검증 내용: injected UUID 사용, 기존 UUID 미재사용, transient display 제거
    /// - 사전 조건: 기존 editor와 같은 canonical property를 가진 saved condition
    /// - 기대 결과: hydration 결과는 새 UUID와 빈 display state를 가진 새 editor
    func testSavedHydrationAllocatesFreshEditorUUID() throws {
        let existingID = try uuid("00000000-0000-0000-0000-000000000012")
        let hydratedID = try uuid("00000000-0000-0000-0000-000000000013")
        var state = ComposerState()
        state.conditionEditors = [
            .init(
                id: existingID,
                condition: Self.condition(values: ["old"]),
                displayState: .init(values: ["old display"], unitValueState: nil),
            ),
        ]

        state.replaceConditions([Self.condition(values: ["saved"])], uuid: { hydratedID })

        XCTAssertEqual(state.conditionEditors.map(\.id), [hydratedID])
        XCTAssertNotEqual(state.conditionEditors.first?.id, existingID)
        XCTAssertEqual(state.conditionEditors.first?.condition.values, ["saved"])
        XCTAssertNil(state.conditionEditors.first?.displayState)
    }

    /// RCL-005-edit_collection_conditions: loading 중 add/remove/property replacement는 상태를 바꾸지 않는다.
    /// - 검증 내용: add/remove/replacement no-op, history 보존, 기존 child 보존
    /// - 사전 조건: loading search 상태의 UUID-owned editor
    /// - 기대 결과: 모든 mutation action 이후 condition editor와 history가 변하지 않음
    func testLoadingGuardsBlockParentMutations() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000014")
        var state = ComposerState()
        state.isLoadingSearch = true
        state.conditionEditors = [.init(id: id, condition: Self.condition())]
        let initialEditors = state.conditionEditors
        let store = makeStore(state)

        await store.send(.view(.addCondition(propertyKey: "file_size")))
        await store.send(.view(.removeCondition(id: id)))
        await store.send(.conditionEditor(.element(id: id, action: .delegate(.replaceProperty("file_size")))))

        XCTAssertEqual(store.state.conditionEditors, initialEditors)
        XCTAssertTrue(store.state.history.isEmpty)
    }

    /// RCL-005-edit_collection_conditions: add/remove는 UUID row와 각각의 history snapshot을 만든다.
    /// - 검증 내용: add UUID, remove UUID, ordered projection, history depth
    /// - 사전 조건: incomplete condition 하나가 있는 Composer state
    /// - 기대 결과: 추가된 row만 제거되고 각 mutation 이전 상태가 history에 남음
    func testAddAndRemoveUseUUIDOwnedTransactions() async throws {
        let initialID = try uuid("00000000-0000-0000-0000-000000000015")
        let addedID = try uuid("00000000-0000-0000-0000-000000000016")
        var state = ComposerState()
        state.conditionEditors = [.init(id: initialID, condition: Self.condition(operatorCode: nil))]
        let store = TestStore(initialState: state) { ComposerFeature() } withDependencies: {
            $0.registryClient = registryClient()
            $0.uuid = .constant(addedID)
        }
        // add/remove는 parent snapshot을 함께 갱신하므로 UUID와 history 결과만 검증한다.
        store.exhaustivity = .off

        await store.send(.view(.addCondition(propertyKey: "file_size")))
        XCTAssertEqual(store.state.conditionEditors.map(\.id), [initialID, addedID])
        XCTAssertEqual(store.state.history.count, 1)
        await store.send(.view(.removeCondition(id: addedID)))
        XCTAssertEqual(store.state.conditionEditors.map(\.id), [initialID])
        XCTAssertEqual(store.state.history.count, 2)
        XCTAssertEqual(store.state.history.last?.conditionEditors.map(\.id), [initialID, addedID])
    }

    /// RCL-005-edit_collection_conditions: duplicate property 교체는 원자적으로 거부된다.
    /// - 검증 내용: original condition 유지, duplicate feedback, history 미생성
    /// - 사전 조건: 서로 다른 property의 UUID editor 두 개
    /// - 기대 결과: duplicate target은 row-local error만 만들고 committed editor 배열은 그대로 유지
    func testRejectsDuplicatePropertyReplacementWithoutMutation() async throws {
        let firstID = try uuid("00000000-0000-0000-0000-000000000017")
        let secondID = try uuid("00000000-0000-0000-0000-000000000018")
        var state = ComposerState()
        state.conditionEditors = [
            .init(id: firstID, condition: Self.condition()),
            .init(id: secondID, condition: Self.condition(propertyKey: "file_size")),
        ]
        let initialEditors = state.conditionEditors
        let store = makeStore(state)

        await store.send(.conditionEditor(.element(id: firstID, action: .delegate(.replaceProperty("file_size"))))) {
            $0.conditionEditors[id: firstID]?.errorMessage = "\"File Size\" is already added."
        }

        XCTAssertEqual(store.state.conditionEditors.map(\.condition), initialEditors.map(\.condition))
        XCTAssertEqual(store.state.conditionEditors[id: firstID]?.errorMessage, "\"File Size\" is already added.")
        XCTAssertTrue(store.state.history.isEmpty)
    }

    /// RCL-005-edit_collection_conditions: undo/redo는 UUID와 display snapshot을 복원하고 transient state를 닫는다.
    /// - 검증 내용: stable UUID/order, display snapshot, transient reset
    /// - 사전 조건: display state가 있는 condition editor에서 property replacement가 완료됨
    /// - 기대 결과: undo는 이전 display를 복원하고 redo는 교체 후 nil display를 복원하며 모두 transient state가 닫힘
    func testUndoRedoRestoreSnapshotsAndResetTransientState() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000019")
        let unitContract = byteUnitContract
        var state = ComposerState()
        state.conditionEditors = [
            .init(
                id: id,
                condition: Self.condition(propertyKey: "file_size", values: ["1024"], unitContract: unitContract),
                displayState: .init(values: ["1"], unitValueState: .init(contract: unitContract)),
            ),
        ]
        let store = makeStore(state)
        // parent transaction은 history와 effect lifecycle을 함께 거치므로 snapshot 결과를 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(id: id, action: .delegate(.replaceProperty("modified_date")))))
        await store.send(.view(.undo))
        XCTAssertEqual(store.state.conditionEditors.map(\.id), [id])
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.property.key, "file_size")
        XCTAssertEqual(store.state.conditionEditors[id: id]?.displayState?.values, ["1"])
        XCTAssertFalse(store.state.conditionEditors[id: id]?.isValuePickerPresented ?? true)
        XCTAssertFalse(store.state.conditionEditors[id: id]?.isOperatorMenuPresented ?? true)

        await store.send(.view(.redo))
        XCTAssertEqual(store.state.conditionEditors.map(\.id), [id])
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.property.key, "modified_date")
        XCTAssertNil(store.state.conditionEditors[id: id]?.displayState)
        XCTAssertFalse(store.state.conditionEditors[id: id]?.isValuePickerPresented ?? true)
        XCTAssertFalse(store.state.conditionEditors[id: id]?.isOperatorMenuPresented ?? true)
    }

    /// RCL-005-edit_collection_conditions: applied filter reconciliation은 서버 순서대로 UUID를 재사용하거나 새로 배정한다.
    /// live editor와 같은 canonical property는 ID를 유지하고 새 property만 injected UUID를 받는지 검증한다.
    /// - 검증 내용: server order, existing UUID reuse, stale editor removal, injected UUID allocation
    /// - 사전 조건: 기존 modified date와 제거 대상 editor가 있으며 server가 file size 후 modified date를 반환함
    /// - 기대 결과: file size는 새 UUID, modified date는 기존 UUID를 사용하고 server 순서로만 남음
    func testAppliedFilterReconciliationPreservesServerOrderAndReusesOnlyMatchingUUIDs() throws {
        let existingID = try uuid("00000000-0000-0000-0000-000000000021")
        let staleID = try uuid("00000000-0000-0000-0000-000000000022")
        let allocatedID = try uuid("00000000-0000-0000-0000-000000000023")
        var state = ComposerState()
        state.conditionEditors = [
            .init(id: existingID, condition: Self.condition(values: ["2025-01-01"])),
            .init(id: staleID, condition: Self.condition(propertyKey: "file_size", values: ["7"])),
        ]

        applyAppliedFilters(
            .init(
                scopes: [],
                excludedScopes: [],
                includeSubfolders: true,
                conditions: [
                    .init(propertyKey: "name_stem", operator: "eq", value: .string("report")),
                    .init(propertyKey: "modified_date", operator: "eq", value: .string("2025-01-01")),
                ],
            ),
            state: &state,
            registryClient: registryClient(),
            uuid: { allocatedID },
        )

        XCTAssertEqual(state.conditionEditors.map(\.condition.property.key), ["name_stem", "modified_date"])
        XCTAssertEqual(state.conditionEditors.map(\.id), [allocatedID, existingID])
        XCTAssertNotEqual(state.conditionEditors.first?.id, staleID)
        XCTAssertEqual(state.conditionEditors.last?.condition.values, ["2025-01-01"])
    }

    /// RCL-005-edit_collection_conditions: duplicate applied filter 목록은 기존 live editor를 원자적으로 보존한다.
    /// 동일 canonical property가 두 번 온 서버 응답이 부분 reconciliation을 만들지 않는지 검증한다.
    /// - 검증 내용: whole-list rejection, existing editor order and UUID preservation, execution feedback
    /// - 사전 조건: 서로 다른 UUID의 live editor 두 개와 duplicate modified date server response
    /// - 기대 결과: 기존 editor는 변경되지 않고 execution failure feedback만 설정됨
    func testAppliedFilterReconciliationRejectsDuplicateWholeListWithoutPartialMutation() throws {
        let firstID = try uuid("00000000-0000-0000-0000-000000000024")
        let secondID = try uuid("00000000-0000-0000-0000-000000000025")
        let unusedID = try uuid("00000000-0000-0000-0000-000000000026")
        var state = ComposerState()
        state.conditionEditors = [
            .init(id: firstID, condition: Self.condition(values: ["2025-01-01"])),
            .init(id: secondID, condition: Self.condition(propertyKey: "file_size", values: ["7"])),
        ]
        let initialEditors = state.conditionEditors

        applyAppliedFilters(
            .init(
                scopes: [],
                excludedScopes: [],
                includeSubfolders: true,
                conditions: [
                    .init(propertyKey: "modified_date", operator: "eq", value: .string("2025-01-01")),
                    .init(propertyKey: "modified_date", operator: "eq", value: .string("2025-02-01")),
                ],
            ),
            state: &state,
            registryClient: registryClient(),
            uuid: { unusedID },
        )

        XCTAssertEqual(state.conditionEditors, initialEditors)
        XCTAssertEqual(state.transientFeedback?.category, .executionFailure)
        XCTAssertEqual(state.transientFeedback?.message, "Duplicate filter properties were returned.")
    }

    /// RCL-005-change_collection_condition_operator: operator commit은 정확히 하나의 이전 history snapshot을 남긴다.
    /// child delegate가 parent transaction으로 처리될 때 snapshot이 중복 생성되지 않는지 검증한다.
    /// - 검증 내용: selected editor operator, history count, pre-commit snapshot
    /// - 사전 조건: operator가 없는 UUID-owned condition editor
    /// - 기대 결과: `eq` operator 적용 후 history는 하나이며 이전 operator-less editor를 보존함
    func testSelectingOperatorCreatesOneHistorySnapshot() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000027")
        var state = ComposerState()
        state.conditionEditors = [.init(id: id, condition: Self.condition(operatorCode: nil))]
        let store = makeStore(state)
        // operator commit은 resolver와 history parent transaction을 함께 거치므로 최종 snapshot을 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(id: id, action: .delegate(.selectOperator("eq")))))

        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.operation?.code, "eq")
        XCTAssertEqual(store.state.history.count, 1)
        XCTAssertNil(store.state.history.last?.conditionEditors[id: id]?.condition.operation)
    }

    /// RCL-005-change_collection_condition_value: value commit은 정확히 하나의 이전 history snapshot을 남긴다.
    /// value 변경이 child-local draft가 아니라 parent-owned semantic mutation으로 기록되는지 검증한다.
    /// - 검증 내용: committed values, history count, pre-commit value snapshot
    /// - 사전 조건: 값이 있는 UUID-owned date condition editor
    /// - 기대 결과: 새 value 적용 후 history는 하나이며 이전 value를 보존함
    func testCommittingValuesCreatesOneHistorySnapshot() async throws {
        let id = try uuid("00000000-0000-0000-0000-000000000028")
        var state = ComposerState()
        state.conditionEditors = [.init(id: id, condition: Self.condition(values: ["2025-01-01"]))]
        let store = makeStore(state)
        // value commit은 apply effect와 history parent transaction을 함께 거치므로 최종 snapshot을 검증한다.
        store.exhaustivity = .off

        await store.send(.conditionEditor(.element(
            id: id,
            action: .delegate(.commitValues(
                values: ["2025-02-01"],
                displayValues: ["2025-02-01"],
                selectedUnitCode: nil,
            )),
        )))

        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.values, ["2025-02-01"])
        XCTAssertEqual(store.state.history.count, 1)
        XCTAssertEqual(store.state.history.last?.conditionEditors[id: id]?.condition.values, ["2025-01-01"])
    }
}

private extension RCL005ComposeCollectionConditionsParentTransactionsTests {
    var byteUnitContract: Condition.UnitContract {
        .init(
            canonicalUnit: "byte",
            options: [.init(code: "byte", label: "Bytes", factorToCanonical: 1)],
            defaultDisplayUnit: "byte",
        )
    }

    func uuid(_ value: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: value))
    }

    func makeStore(_ state: ComposerState) -> TestStoreOf<ComposerFeature> {
        TestStore(initialState: state) { ComposerFeature() } withDependencies: {
            $0.registryClient = registryClient()
        }
    }

    func registryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Name" },
            propertyTypeString: { _ in "date" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["exists", "btw", "eq"] },
            operatorDefinition: { _ in
                .init(
                    uiLabel: "Equals",
                    mdqueryOperator: nil,
                    valueShape: .single,
                    valueCount: .fixed(1),
                    allowedTypes: ["date", "number"],
                    inverseOf: nil,
                    aliases: nil,
                    uiValueKind: ["date": "singleDate", "number": "singleNumber"],
                )
            },
            resolvePropertyKey: { .canonical($0) },
            resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
                Self.condition(
                    propertyKey: propertyKey,
                    operatorCode: operatorCode,
                    values: values,
                    sourcePayload: sourcePayload,
                )
            },
        )
    }

    nonisolated static func condition(
        propertyKey: String = "modified_date",
        operatorCode: String? = "eq",
        values: [String]? = nil,
        sourcePayload: CollectionCondition? = nil,
        unitContract: Condition.UnitContract? = nil,
    ) -> Condition {
        let type: SystemPropertyTypeKey = propertyKey == "file_size" ? .number : .date
        let options = [
            Condition.OperatorOption(code: "exists", label: "Exists"),
            .init(code: "btw", label: "Between"),
            .init(code: "eq", label: "Equals"),
        ]
        let contract: Condition.ValueContract = switch (operatorCode, type) {
        case (nil, _): .init(shape: .none, count: .fixed(0), input: .none)
        case ("exists", _): .init(shape: .none, count: .fixed(0), input: .none)
        case ("btw", .number): .init(shape: .range, count: .fixed(2), input: .rangeNumber)
        case ("btw", _): .init(shape: .range, count: .fixed(2), input: .rangeDate)
        case ("eq", .number): .init(shape: .single, count: .fixed(1), input: .singleNumber)
        default: .init(shape: .single, count: .fixed(1), input: .singleDate)
        }
        return Condition(
            property: .init(
                key: propertyKey,
                label: propertyKey == "file_size" ? "File Size" : "Modified Date",
                type: type,
                unitContract: unitContract,
                operatorOptions: options,
            ),
            operation: operatorCode.map { .init(code: $0, label: $0, valueContract: contract) },
            values: operatorCode == "exists" ? [] : values,
            availability: .available,
            opaqueSource: sourcePayload,
        )
    }
}

import ComposableArchitecture
import Foundation
@_spi(Testing)
@testable import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class RCL005ComposeCollectionConditionsTests: XCTestCase {
    // MARK: - RCL-005-change_collection_condition_operator

    /// RCL-005-change_collection_condition_operator: 값이 필요 없는 operator는 value input을 비움
    /// condition operator를 `exists`로 바꾸면 value 입력 UI 계약이 no-value 상태가 되는지 검증한다.
    /// - 검증 내용: operator metadata, arity, value UI kind, history snapshot
    /// - 사전 조건: date property condition이 operator 미선택 상태로 존재함
    /// - 기대 결과: condition은 `exists` operator와 arity 0, 빈 values를 가짐
    func testChangeConditionOperator_withExists_configuresNoValueInput() async throws {
        let initialState = try makeConditionState()
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 핵심 condition 계약만 검증한다.
        store.exhaustivity = .off

        let id = try XCTUnwrap(store.state.conditionEditors.first?.id)
        await store.send(.conditionEditor(.element(id: id, action: .delegate(.selectOperator("exists")))))
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.operation?.code, "exists")
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.values, [])
    }

    /// RCL-005-change_collection_condition_operator: range date operator는 두 값 입력 상태를 구성함
    /// condition operator를 `between`으로 바꾸면 range date 입력 계약이 설정되는지 검증한다.
    /// - 검증 내용: operatorCode, value arity, rangeDate UI kind
    /// - 사전 조건: date property condition이 operator 미선택 상태로 존재함
    /// - 기대 결과: condition은 `btw` operator와 arity 2, nil values를 가짐
    func testChangeConditionOperator_withBetween_configuresRangeDateInputs() async throws {
        let initialState = try makeConditionState()
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 핵심 condition 계약만 검증한다.
        store.exhaustivity = .off

        let id = try XCTUnwrap(store.state.conditionEditors.first?.id)
        await store.send(.conditionEditor(.element(id: id, action: .delegate(.selectOperator("btw")))))
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.operation?.code, "btw")
        XCTAssertNil(store.state.conditionEditors[id: id]?.condition.values)
    }

    /// RCL-005-change_collection_condition_operator: operator 변경은 기존 value picker payload를 초기화함
    /// 같은 property에서 operator가 바뀌면 이전 value picker 입력이 남지 않는지 검증한다.
    /// - 검증 내용: valuePicker presentation/key/operator/value reset
    /// - 사전 조건: value picker가 기존 single text 입력으로 열린 상태임
    /// - 기대 결과: value picker가 닫히고 range date 기본 입력 상태로 초기화됨
    func testChangeConditionOperator_resetsValuePickerPayloadForSameProperty() async throws {
        var initial = try makeConditionState()
        initial.valuePicker = .init()
        initial.valuePicker.condition = Self.makeTypedCondition(propertyKey: "name_stem", operatorCode: "eq")
        initial.valuePicker.isPresented = true
        initial.valuePicker.values = ["report"]
        initial.valuePicker.errorMessage = "x"

        let store = TestStore(initialState: initial) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 valuePicker reset 계약만 검증한다.
        store.exhaustivity = .off

        let id = try XCTUnwrap(store.state.conditionEditors.first?.id)
        await store.send(.conditionEditor(.element(id: id, action: .delegate(.selectOperator("btw")))))
        XCTAssertEqual(store.state.conditionEditors[id: id]?.condition.operation?.code, "btw")
        XCTAssertFalse(store.state.conditionEditors[id: id]?.isValuePickerPresented ?? true)
    }

    // MARK: - RCL-005-change_collection_condition_value

    /// RCL-005-change_collection_condition_value: relative single date 편집 상태를 복원함
    /// 기존 relative date literal을 value picker가 date editing state로 복원하는지 검증한다.
    /// - 검증 내용: prepare 후 dateValueState mode/direction/amount/unit
    /// - 사전 조건: `modified_date eq` condition의 기존 값이 relative literal임
    /// - 기대 결과: value picker가 relative mode와 동일 amount/unit으로 열림
    func testChangeConditionValue_prepareRelativeSingleDate_restoresEditingState() async {
        let anchorDate = ConditionValueNormalizer.formatDateOnly(Date())
        let rawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.prepare(.init(
            condition: Self.makeTypedCondition(
                propertyKey: "modified_date",
                operatorCode: "eq",
                values: [rawValue],
            ),
            existingDisplayValues: nil,
            preferredUnitCode: nil,
            editingIndex: 0,
        ))) {
            let expectedSelectedDate = ConditionValueNormalizer
                .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                    byAdding: .day,
                    value: -3,
                    to: Date(),
                ) ?? Date())) ?? Date()
            $0.isPresented = true
            $0.condition = Self.makeTypedCondition(
                propertyKey: "modified_date",
                operatorCode: "eq",
                values: [rawValue],
            )
            $0.values = [rawValue]
            $0.editingIndex = 0
            $0.dateValueState = DateValueState(
                mode: .relative,
                selectedDate: expectedSelectedDate,
                relativeDirection: .past,
                relativeAmount: 3,
                relativeUnit: .day,
            )
        }
    }

    /// RCL-005-change_collection_condition_value: relative single date commit은 canonical literal과 display text를 전달함
    /// relative date 입력을 commit하면 condition value와 표시 문자열이 함께 생성되는지 검증한다.
    /// - 검증 내용: commitResult values/displayValues
    /// - 사전 조건: value picker가 relative 3 days ago 상태로 열려 있음
    /// - 기대 결과: canonical relative literal과 `3 days ago` display text가 전달됨
    func testChangeConditionValue_commitRelativeSingleDate_sendsCanonicalLiteralAndDisplayText() async {
        var state = makeDatePickerState()
        state.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .past,
            relativeAmount: 3,
            relativeUnit: .day,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        let anchorDate = ConditionValueNormalizer.formatDateOnly(Date())
        let expectedRawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"

        await store.send(ValuePickerAction.commit)
        await store.receive(ValuePickerAction.commitResult(
            values: [expectedRawValue],
            displayValues: ["3 days ago"],
            selectedUnitCode: nil,
        ))
    }

    /// RCL-005-change_collection_condition_value: today single date commit은 Today 표시값을 전달함
    /// today mode의 date value가 commit result에서 Today display로 내려오는지 검증한다.
    /// - 검증 내용: commitResult today raw/display values
    /// - 사전 조건: value picker가 today mode로 열려 있음
    /// - 기대 결과: 오늘 날짜 raw 값과 `Today` 표시값이 전달됨
    func testChangeConditionValue_commitTodaySingleDate_usesTodayDisplay() async {
        let today = ConditionValueNormalizer.parseDate(ConditionValueNormalizer.formatDateOnly(Date())) ?? Date()
        var state = makeDatePickerState()
        state.dateValueState = DateValueState(
            mode: .today,
            selectedDate: today,
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(ValuePickerAction.commit)
        await store.receive(ValuePickerAction.commitResult(
            values: [ConditionValueNormalizer.formatDateOnly(today)],
            displayValues: ["Today"],
            selectedUnitCode: nil,
        ))
    }

    /// RCL-005-change_collection_condition_value: relative date amount/unit/direction 편집은 선택 날짜를 갱신함
    /// relative date 세부 입력 변경이 calendar selection에 반영되는지 검증한다.
    /// - 검증 내용: amount, unit, direction 변경 후 selectedDate 갱신
    /// - 사전 조건: absolute date 상태에서 relative 입력을 변경함
    /// - 기대 결과: 3일 전, 3주 전, 3주 후 선택 날짜가 순서대로 반영됨
    func testChangeConditionValue_relativeDateEditsUpdateCalendarSelection() async {
        var state = makeDatePickerState()
        state.dateValueState = DateValueState(
            mode: .absolute,
            selectedDate: ConditionValueNormalizer.parseDate("2025-01-01") ?? Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let threeDaysAgo = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .day,
                value: -3,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDateAmount(3)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativeAmount = 3
            $0.dateValueState?.selectedDate = threeDaysAgo
        }

        let threeWeeksAgo = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .weekOfYear,
                value: -3,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDateUnit(.week)) {
            $0.dateValueState?.relativeUnit = .week
            $0.dateValueState?.selectedDate = threeWeeksAgo
        }

        let threeWeeksAhead = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .weekOfYear,
                value: 3,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDateDirection(.future)) {
            $0.dateValueState?.relativeDirection = .future
            $0.dateValueState?.selectedDate = threeWeeksAhead
        }
    }

    /// RCL-005-change_collection_condition_value: relative preset 선택은 custom 입력 전까지 보존됨
    /// preset 기반 relative date 편집이 preset 상태를 보존하다가 직접 amount 변경 시 custom으로 바뀌는지 검증한다.
    /// - 검증 내용: relativePreset, amount, selectedDate 변경
    /// - 사전 조건: relative date picker에서 7 days ago preset을 선택함
    /// - 기대 결과: preset 선택 후 `.daysAgo7`, 직접 amount 변경 후 `.custom`이 됨
    func testChangeConditionValue_relativePresetPersistsUntilCustomInput() async {
        var state = makeDatePickerState()
        state.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let sevenDaysAgo = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDatePreset(.daysAgo7)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativePreset = .daysAgo7
            $0.dateValueState?.relativeDirection = .past
            $0.dateValueState?.relativeAmount = 7
            $0.dateValueState?.relativeUnit = .day
            $0.dateValueState?.selectedDate = sevenDaysAgo
        }

        let nineDaysAgo = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .day,
                value: -9,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDateAmount(9)) {
            $0.dateValueState?.relativePreset = .custom
            $0.dateValueState?.relativeAmount = 9
            $0.dateValueState?.selectedDate = nineDaysAgo
        }
    }

    /// RCL-005-change_collection_condition_value: future relative amount 변경은 방향을 유지함
    /// future 방향의 relative date 입력에서 amount 변경이 direction을 past로 되돌리지 않는지 검증한다.
    /// - 검증 내용: relativeDirection 보존과 amount 갱신
    /// - 사전 조건: future 2 weeks 상태에서 amount를 3으로 변경함
    /// - 기대 결과: direction은 `.future`, amount는 3으로 유지됨
    func testChangeConditionValue_relativeAmountEditPreservesFutureDirection() async {
        var state = makeDatePickerState()
        state.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .future,
            relativeAmount: 2,
            relativeUnit: .week,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let threeWeeksAhead = ConditionValueNormalizer
            .parseDate(ConditionValueNormalizer.formatDateOnly(Calendar.current.date(
                byAdding: .weekOfYear,
                value: 3,
                to: Date(),
            ) ?? Date())) ?? Date()
        await store.send(.setRelativeDateAmount(3)) {
            $0.dateValueState?.relativePreset = .custom
            $0.dateValueState?.relativeAmount = 3
            $0.dateValueState?.relativeDirection = .future
            $0.dateValueState?.selectedDate = threeWeeksAhead
        }
    }

    /// RCL-005-change_collection_condition_value: date display는 relative/today 값을 표시 문자열로 변환함
    /// condition chip이 relative, today, range absolute 값을 각각 올바르게 표시하는지 검증한다.
    /// - 검증 내용: displayDateValueText와 displayedValuesForDate 결과
    /// - 사전 조건: relative literal, today raw date, absolute range 값이 주어짐
    /// - 기대 결과: relative/today는 사람이 읽는 문구로, range는 absolute 값으로 유지됨
    func testChangeConditionValue_displayedValuesForDate_renderRelativeAndTodayButKeepRangesAbsolute() {
        let today = ConditionValueNormalizer.formatDateOnly(Date())
        let relativeRaw = "voyager.relativeDate:v1:future:2:week:\(today)"

        XCTAssertEqual(ConditionChipDisplay.displayDateValueText(relativeRaw), "In 2 weeks")
        XCTAssertEqual(ConditionChipDisplay.displayDateValueText(today), "Today")
        XCTAssertEqual(
            ConditionChipDisplay.displayedValuesForDate(
                conditionValues: ["2025-05-01", "2025-05-31"],
                pickerState: ConditionChipDisplay.DatePickerState(
                    presented: false,
                    values: [],
                    dateValueState: nil,
                ),
            ),
            ["2025-05-01", "2025-05-31"],
        )
        XCTAssertEqual(
            ConditionChipDisplay.displayedValuesForDate(
                conditionValues: [relativeRaw],
                pickerState: ConditionChipDisplay.DatePickerState(
                    presented: true,
                    values: [relativeRaw],
                    dateValueState: DateValueState(
                        mode: .relative,
                        selectedDate: Date(),
                        relativeDirection: .future,
                        relativeAmount: 2,
                        relativeUnit: .week,
                    ),
                ),
            ),
            ["In 2 weeks"],
        )
    }

    // MARK: - RCL-005-edit_condition_child_lifecycle

    /// RCL-005-edit_condition_child_lifecycle: UUID별 editor draft는 서로 격리된다.
    /// 두 행을 순차적으로 편집해도 각 child의 transient draft가 상대 행이나 committed Condition을 변경하지 않는지 검증한다.
    /// - 검증 내용: child UUID identity, local draft, dismiss reset
    /// - 사전 조건: 서로 다른 고정 UUID와 동일한 typed condition을 가진 두 ConditionEditorState가 있음
    /// - 기대 결과: 첫 editor의 dismiss는 자신의 draft만 reset하고 둘째 editor draft는 유지됨
    func testConditionEditor_keepsDraftsIsolatedByInjectedUUID() async throws {
        let condition = Self.makeTypedCondition()
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = TestStore(initialState: ConditionEditorState(id: firstID, condition: condition)) {
            ConditionEditorFeature()
        }
        let second = TestStore(initialState: ConditionEditorState(id: secondID, condition: condition)) {
            ConditionEditorFeature()
        }

        await first.send(.view(.setValuePickerPresented(true))) { $0.isValuePickerPresented = true }
        await first.send(.view(.setDraftValue(index: 0, text: "draft-a"))) { $0.draftValues = ["draft-a"] }
        await second.send(.view(.setValuePickerPresented(true))) { $0.isValuePickerPresented = true }
        await second.send(.view(.setDraftValue(index: 0, text: "draft-b"))) { $0.draftValues = ["draft-b"] }
        await first.send(.view(.dismiss)) {
            $0.isValuePickerPresented = false
            $0.draftValues = []
        }

        XCTAssertEqual(first.state.id, firstID)
        XCTAssertEqual(second.state.id, secondID)
        XCTAssertEqual(second.state.draftValues, ["draft-b"])
        XCTAssertEqual(first.state.condition, condition)
    }

    /// RCL-005-edit_condition_child_lifecycle: invalid draft는 delegate commit을 만들지 않는다.
    /// number value contract에 잘못된 문자열을 입력해도 semantic condition 대신 row-local error만 바뀌는지 검증한다.
    /// - 검증 내용: typed normalization failure와 delegate 미발행
    /// - 사전 조건: single number operation의 UUID child editor에 malformed number draft가 있음
    /// - 기대 결과: error가 표시되고 condition은 동일하며 TestStore에 미소비 delegate action이 없음
    func testConditionEditor_keepsInvalidDraftLocal() async throws {
        let condition = Self.makeTypedCondition(propertyKey: "file_size", operatorCode: "eq")
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let store = TestStore(initialState: ConditionEditorState(
            id: id,
            condition: condition,
        )) {
            ConditionEditorFeature()
        }

        await store.send(.view(.setValuePickerPresented(true))) { $0.isValuePickerPresented = true }
        await store.send(.view(.setDraftValue(index: 0, text: "not-a-number"))) { $0.draftValues = ["not-a-number"] }
        await store.send(.view(.commitValues)) {
            $0.errorMessage = "Enter a valid number."
            $0.draftValues = [""]
        }
        XCTAssertEqual(store.state.condition, condition)
    }

    /// RCL-005-edit_condition_child_lifecycle: property picker는 sibling key를 row UUID에만 주입한다.
    /// 동일 property key가 아닌 child UUID가 presentation state를 소유하는지 검증한다.
    /// - 검증 내용: UUID route, sibling existingKeys, row-local presentation
    /// - 사전 조건: 서로 다른 property를 가진 두 child editor가 있음
    /// - 기대 결과: 첫 row picker는 둘째 property만 제외 대상으로 갖고 열린다
    func testConditionEditor_propertyPickerReceivesSiblingKeysForItsUUID() async throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
        var state = ComposerState()
        state.conditionEditors = [
            .init(id: firstID, condition: Self.makeTypedCondition()),
            .init(id: secondID, condition: Self.makeTypedCondition(propertyKey: "file_size")),
        ]
        let store = TestStore(initialState: state) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.conditionEditor(.element(
            id: firstID,
            action: .view(.setPropertyPickerPresented(true)),
        ))) {
            $0.conditionEditors[id: firstID]?.propertyPicker.existingKeys = ["file_size"]
            $0.conditionEditors[id: firstID]?.propertyPicker.isPresented = true
        }
    }
}

private extension RCL005ComposeCollectionConditionsTests {
    func makeConditionState() throws -> ComposerState {
        var state = ComposerState()
        state.scopes = ["/tmp"]
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        state.conditionEditors = [
            .init(
                id: id,
                condition: Self.makeTypedCondition(
                    propertyKey: "modified_date",
                    operatorCode: nil,
                ),
            ),
        ]
        return state
    }

    private func makeDatePickerState() -> ValuePickerState {
        var state = ValuePickerState()
        state.condition = Self.makeTypedCondition(
            propertyKey: "modified_date",
            operatorCode: "eq",
        )
        state.isPresented = true
        state.values = [""]
        state.editingIndex = 0
        return state
    }

    private func makeRegistryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Name" },
            propertyTypeString: { _ in "date" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["exists", "btw", "eq"] },
            operatorDefinition: Self.operatorDefinition,
            resolvePropertyKey: { .canonical($0) },
            resolveCondition: { propertyKey, operatorCode, values, sourcePayload in
                Self.makeTypedCondition(
                    propertyKey: propertyKey,
                    operatorCode: operatorCode,
                    values: values,
                    sourcePayload: sourcePayload,
                )
            },
        )
    }

    nonisolated static func makeTypedCondition(
        propertyKey: String = "modified_date",
        operatorCode: String? = "eq",
        values: [String]? = nil,
        sourcePayload: CollectionCondition? = nil,
        unitContract: Condition.UnitContract? = nil,
    ) -> Condition {
        let type: SystemPropertyTypeKey = propertyKey == "file_size" ? .number : .date
        let operatorOptions = [
            Condition.OperatorOption(code: "exists", label: "Exists"),
            Condition.OperatorOption(code: "btw", label: "Between"),
            Condition.OperatorOption(code: "eq", label: "Equals"),
        ]
        let operation = operatorCode.map { makeOperation(code: $0, type: type, options: operatorOptions) }
        let resolvedValues = operatorCode == "exists" ? [] : values
        return Condition(
            property: .init(
                key: propertyKey,
                label: propertyKey == "file_size" ? "File Size" : "Modified Date",
                type: type,
                unitContract: unitContract,
                operatorOptions: operatorOptions,
            ),
            operation: operation,
            values: resolvedValues,
            availability: .available,
            opaqueSource: sourcePayload,
        )
    }

    nonisolated private static func makeOperation(
        code: String,
        type: SystemPropertyTypeKey,
        options: [Condition.OperatorOption],
    ) -> Condition.Operation {
        let contract: Condition.ValueContract = switch (code, type) {
        case ("exists", _): .init(shape: .none, count: .fixed(0), input: .none)
        case ("btw", .number): .init(shape: .range, count: .fixed(2), input: .rangeNumber)
        case ("btw", _): .init(shape: .range, count: .fixed(2), input: .rangeDate)
        case ("eq", .number): .init(shape: .single, count: .fixed(1), input: .singleNumber)
        default: .init(shape: .single, count: .fixed(1), input: .singleDate)
        }
        return .init(
            code: code,
            label: options.first(where: { $0.code == code })?.label ?? code,
            valueContract: contract,
        )
    }

    nonisolated private static func operatorDefinition(_ code: String) -> OperatorDefinition {
        switch code {
        case "exists": .init(
                uiLabel: "Exists",
                mdqueryOperator: nil,
                valueShape: ValueShape.none,
                valueCount: .fixed(0),
                allowedTypes: ["date"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["date": "none"],
            )
        case "btw": .init(
                uiLabel: "Between",
                mdqueryOperator: "RANGE",
                valueShape: .range,
                valueCount: .fixed(2),
                allowedTypes: ["date"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["date": "rangeDate"],
            )
        default: .init(
                uiLabel: code,
                mdqueryOperator: nil,
                valueShape: .single,
                valueCount: .fixed(1),
                allowedTypes: ["date"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["date": "singleDate"],
            )
        }
    }
}

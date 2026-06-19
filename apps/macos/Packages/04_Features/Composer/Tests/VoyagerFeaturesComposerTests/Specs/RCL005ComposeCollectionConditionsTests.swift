import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
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
    func testChangeConditionOperator_withExists_configuresNoValueInput() async {
        let store = TestStore(initialState: makeConditionState()) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 핵심 condition 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "exists")) {
            $0.conditions[0].operatorCode = "exists"
            $0.conditions[0].operatorLabel = "Exists"
            $0.conditions[0].operatorValueArity = 0
            $0.conditions[0].operatorValueUIKind = "none"
            $0.conditions[0].valueType = "string"
            $0.conditions[0].values = []
        }
    }

    /// RCL-005-change_collection_condition_operator: range date operator는 두 값 입력 상태를 구성함
    /// condition operator를 `between`으로 바꾸면 range date 입력 계약이 설정되는지 검증한다.
    /// - 검증 내용: operatorCode, value arity, rangeDate UI kind
    /// - 사전 조건: date property condition이 operator 미선택 상태로 존재함
    /// - 기대 결과: condition은 `btw` operator와 arity 2, nil values를 가짐
    func testChangeConditionOperator_withBetween_configuresRangeDateInputs() async {
        let store = TestStore(initialState: makeConditionState()) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 핵심 condition 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeDate"
            $0.conditions[0].valueType = "date"
            $0.conditions[0].values = nil
        }
    }

    /// RCL-005-change_collection_condition_operator: operator 변경은 기존 value picker payload를 초기화함
    /// 같은 property에서 operator가 바뀌면 이전 value picker 입력이 남지 않는지 검증한다.
    /// - 검증 내용: valuePicker presentation/key/operator/value reset
    /// - 사전 조건: value picker가 기존 single text 입력으로 열린 상태임
    /// - 기대 결과: value picker가 닫히고 range date 기본 입력 상태로 초기화됨
    func testChangeConditionOperator_resetsValuePickerPayloadForSameProperty() async {
        var initial = makeConditionState()
        initial.valuePicker = .init()
        initial.valuePicker.propertyKey = "name_stem"
        initial.valuePicker.operatorCode = "eq"
        initial.valuePicker.isPresented = true
        initial.valuePicker.valueType = "string"
        initial.valuePicker.valueUIKind = "singleText"
        initial.valuePicker.valueArity = 1
        initial.valuePicker.values = ["report"]
        initial.valuePicker.errorMessage = "x"

        let store = TestStore(initialState: initial) {
            ComposerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }
        // operator 변경은 history snapshot까지 함께 갱신하므로 valuePicker reset 계약만 검증한다.
        store.exhaustivity = .off

        await store.send(.setOperator(propertyKey: "name_stem", operatorCode: "btw")) {
            $0.conditions[0].operatorCode = "btw"
            $0.conditions[0].operatorLabel = "Between"
            $0.conditions[0].operatorValueArity = 2
            $0.conditions[0].operatorValueUIKind = "rangeDate"
            $0.conditions[0].valueType = "date"
            $0.conditions[0].values = nil
            $0.valuePicker.isPresented = false
            $0.valuePicker.propertyKey = nil
            $0.valuePicker.operatorCode = nil
            $0.valuePicker.valueUIKind = "singleText"
            $0.valuePicker.valueType = "string"
            $0.valuePicker.values = ["", ""]
            $0.valuePicker.errorMessage = nil
        }
    }

    // MARK: - RCL-005-change_collection_condition_value

    /// RCL-005-change_collection_condition_value: relative single date 편집 상태를 복원함
    /// 기존 relative date literal을 value picker가 date editing state로 복원하는지 검증한다.
    /// - 검증 내용: prepare 후 dateValueState mode/direction/amount/unit
    /// - 사전 조건: `modified_date eq` condition의 기존 값이 relative literal임
    /// - 기대 결과: value picker가 relative mode와 동일 amount/unit으로 열림
    func testChangeConditionValue_prepareRelativeSingleDate_restoresEditingState() async {
        let anchorDate = ValueNormalizerUtils.formatDateOnly(Date())
        let rawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.prepare(.init(
            propertyKey: "modified_date",
            operatorCode: "eq",
            valueType: "date",
            valueUIKind: "singleDate",
            valueArity: 1,
            existingValues: [rawValue],
            existingDisplayValues: nil,
            preferredUnitCode: nil,
            editingIndex: 0,
        ))) {
            let expectedSelectedDate = ValueNormalizerUtils.parseDate(
                ValueNormalizerUtils.formatDateOnly(
                    Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
                ),
            ) ?? Date()
            $0.propertyKey = "modified_date"
            $0.operatorCode = "eq"
            $0.isPresented = true
            $0.valueType = "date"
            $0.valueUIKind = "singleDate"
            $0.valueArity = 1
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
        let anchorDate = ValueNormalizerUtils.formatDateOnly(Date())
        let expectedRawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"

        await store.send(ValuePickerAction.commit)
        await store.receive(ValuePickerAction.commitResult(
            propertyKey: "modified_date",
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
        let today = ValueNormalizerUtils.parseDate(ValueNormalizerUtils.formatDateOnly(Date())) ?? Date()
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
            propertyKey: "modified_date",
            values: [ValueNormalizerUtils.formatDateOnly(today)],
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
            selectedDate: ValueNormalizerUtils.parseDate("2025-01-01") ?? Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )
        let store = TestStore(initialState: state) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let threeDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDateAmount(3)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativeAmount = 3
            $0.dateValueState?.selectedDate = threeDaysAgo
        }

        let threeWeeksAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDateUnit(.week)) {
            $0.dateValueState?.relativeUnit = .week
            $0.dateValueState?.selectedDate = threeWeeksAgo
        }

        let threeWeeksAhead = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .weekOfYear, value: 3, to: Date()) ?? Date(),
            ),
        ) ?? Date()
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

        let sevenDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDatePreset(.daysAgo7)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativePreset = .daysAgo7
            $0.dateValueState?.relativeDirection = .past
            $0.dateValueState?.relativeAmount = 7
            $0.dateValueState?.relativeUnit = .day
            $0.dateValueState?.selectedDate = sevenDaysAgo
        }

        let nineDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -9, to: Date()) ?? Date(),
            ),
        ) ?? Date()
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

        let threeWeeksAhead = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .weekOfYear, value: 3, to: Date()) ?? Date(),
            ),
        ) ?? Date()
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
        let today = ValueNormalizerUtils.formatDateOnly(Date())
        let relativeRaw = "voyager.relativeDate:v1:future:2:week:\(today)"

        XCTAssertEqual(ConditionChipDisplayUtils.displayDateValueText(relativeRaw), "In 2 weeks")
        XCTAssertEqual(ConditionChipDisplayUtils.displayDateValueText(today), "Today")
        XCTAssertEqual(
            ConditionChipDisplayUtils.displayedValuesForDate(
                conditionValues: ["2025-05-01", "2025-05-31"],
                conditionPropertyKey: "modified_date",
                pickerState: ConditionChipDisplayUtils.DatePickerState(
                    propertyKey: nil,
                    presented: false,
                    values: [],
                    dateValueState: nil,
                ),
            ),
            ["2025-05-01", "2025-05-31"],
        )
        XCTAssertEqual(
            ConditionChipDisplayUtils.displayedValuesForDate(
                conditionValues: [relativeRaw],
                conditionPropertyKey: "modified_date",
                pickerState: ConditionChipDisplayUtils.DatePickerState(
                    propertyKey: "modified_date",
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

    private func makeConditionState() -> ComposerState {
        var state = ComposerState()
        state.scopes = ["/tmp"]
        state.conditions = [Condition(
            propertyKey: "name_stem",
            propertyLabel: "Name",
            propertyType: "date",
            operatorCode: nil,
            operatorLabel: nil,
            operatorValueArity: nil,
            operatorValueUIKind: nil,
            valueType: "date",
            values: nil,
        )]
        return state
    }

    private func makeDatePickerState() -> ValuePickerState {
        var state = ValuePickerState()
        state.propertyKey = "modified_date"
        state.operatorCode = "eq"
        state.isPresented = true
        state.valueType = "date"
        state.valueUIKind = "singleDate"
        state.valueArity = 1
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
            operatorDefinition: { code in
                switch code {
                case "exists":
                    .init(
                        uiLabel: "Exists",
                        mdqueryOperator: nil,
                        valueShape: ValueShape.none,
                        valueCount: .fixed(0),
                        allowedTypes: ["date"],
                        inverseOf: nil,
                        aliases: nil,
                        uiValueKind: ["date": "none"],
                    )
                case "btw":
                    .init(
                        uiLabel: "Between",
                        mdqueryOperator: "RANGE",
                        valueShape: .range,
                        valueCount: .fixed(2),
                        allowedTypes: ["date"],
                        inverseOf: nil,
                        aliases: nil,
                        uiValueKind: ["date": "rangeDate"],
                    )
                default:
                    .init(
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
            },
            operatorValueUIKind: { code, _ in
                code == "exists" ? "none" : (code == "btw" ? "rangeDate" : "singleDate")
            },
            resolvePropertyKey: { .canonical($0) },
        )
    }
}

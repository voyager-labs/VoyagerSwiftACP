import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import XCTest

@MainActor
final class ValuePickerDateEditingTests: XCTestCase {
    func testPrepareRelativeSingleDateRestoresRelativeEditingState() async {
        let anchorDate = ValueNormalizerUtils.formatDateOnly(Date())
        let rawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"
        let store = TestStore(initialState: ValuePickerState()) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(
            .prepare(
                .init(
                    propertyKey: "modified_date",
                    operatorCode: "eq",
                    valueType: "date",
                    valueUIKind: "singleDate",
                    valueArity: 1,
                    existingValues: [rawValue],
                    existingDisplayValues: nil,
                    preferredUnitCode: nil,
                    editingIndex: 0,
                ),
            ),
        ) {
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

    func testCommitRelativeSingleDateSendsCanonicalLiteralAndDisplayText() async {
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .past,
            relativeAmount: 3,
            relativeUnit: .day,
        )

        let store = TestStore(
            initialState: initialState,
        ) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let anchorDate = ValueNormalizerUtils.formatDateOnly(Date())
        let expectedRawValue = "voyager.relativeDate:v1:past:3:day:\(anchorDate)"

        await store.send(ValuePickerAction.commit)
        await store.receive(
            ValuePickerAction.commitResult(
                propertyKey: "modified_date",
                values: [expectedRawValue],
                displayValues: ["3 days ago"],
                selectedUnitCode: nil,
            ),
        )
    }

    func testCommitTodaySingleDateUsesTodayDisplay() async {
        let today = ValueNormalizerUtils.parseDate(ValueNormalizerUtils.formatDateOnly(Date())) ?? Date()
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .today,
            selectedDate: today,
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )

        let store = TestStore(
            initialState: initialState,
        ) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(ValuePickerAction.commit)
        await store.receive(
            ValuePickerAction.commitResult(
                propertyKey: "modified_date",
                values: [ValueNormalizerUtils.formatDateOnly(today)],
                displayValues: ["Today"],
                selectedUnitCode: nil,
            ),
        )
    }

    func testRelativeDateEditsUpdateCalendarSelection() async {
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .absolute,
            selectedDate: ValueNormalizerUtils.parseDate("2025-01-01") ?? Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )

        let store = TestStore(initialState: initialState) {
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

    func testRelativeModeDateSelectionKeepsCalendarDerivedFromRelativeFields() async {
        let oneWeekAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        let clickedDate = ValueNormalizerUtils.parseDate("2025-07-04") ?? Date()
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: clickedDate,
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .week,
        )

        let store = TestStore(initialState: initialState) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        await store.send(.setDateSelection(clickedDate)) {
            $0.dateValueState?.selectedDate = oneWeekAgo
        }
    }

    func testRelativePresetSelectionPersistsUntilCustomInput() async {
        var initialState = ValuePickerState()
        initialState.propertyKey = "modified_date"
        initialState.operatorCode = "eq"
        initialState.isPresented = true
        initialState.valueType = "date"
        initialState.valueUIKind = "singleDate"
        initialState.valueArity = 1
        initialState.values = [""]
        initialState.editingIndex = 0
        initialState.dateValueState = DateValueState(
            mode: .relative,
            selectedDate: Date(),
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )

        let store = TestStore(initialState: initialState) {
            ValuePickerFeature()
        } withDependencies: {
            $0.registryClient = makeRegistryClient()
        }

        let sevenDaysAgo = ValueNormalizerUtils.parseDate(
            ValueNormalizerUtils.formatDateOnly(
                Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            ),
        ) ?? Date()
        await store.send(.setRelativeDatePreset(.last7Days)) {
            $0.dateValueState?.mode = .relative
            $0.dateValueState?.relativePreset = .last7Days
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

    func testDisplayedValuesForDateRenderRelativeAndTodayButKeepRangesAbsolute() {
        let today = ValueNormalizerUtils.formatDateOnly(Date())
        let relativeRaw = "voyager.relativeDate:v1:future:2:week:\(today)"

        XCTAssertEqual(ConditionChipDisplayUtils.displayedDateText(relativeRaw), "In 2 weeks")
        XCTAssertEqual(ConditionChipDisplayUtils.displayedDateText(today), "Today")
        XCTAssertEqual(
            ConditionChipDisplayUtils.displayedValuesForDate(
                conditionValues: ["2025-05-01", "2025-05-31"],
                conditionPropertyKey: "modified_date",
                pickerPropertyKey: nil,
                pickerPresented: false,
                pickerValues: [],
                pickerDateValueState: nil,
            ),
            ["2025-05-01", "2025-05-31"],
        )
        XCTAssertEqual(
            ConditionChipDisplayUtils.displayedValuesForDate(
                conditionValues: [relativeRaw],
                conditionPropertyKey: "modified_date",
                pickerPropertyKey: "modified_date",
                pickerPresented: true,
                pickerValues: [relativeRaw],
                pickerDateValueState: DateValueState(
                    mode: .relative,
                    selectedDate: Date(),
                    relativeDirection: .future,
                    relativeAmount: 2,
                    relativeUnit: .week,
                ),
            ),
            ["In 2 weeks"],
        )
    }

    private func makeRegistryClient() -> RegistryClient {
        .init(
            allProperties: { [] },
            labelForKey: { _ in "Modified" },
            propertyTypeString: { _ in "date" },
            propertyUnitSpec: { _ in nil },
            operatorCodes: { _ in ["eq"] },
            operatorDefinition: { code in
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
            },
            operatorValueUIKind: { _, _ in "singleDate" },
            resolvePropertyKey: { .canonical($0) },
        )
    }
}

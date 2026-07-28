import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

func applyRelativePreset(_ preset: DateValueState.RelativePreset, to dateValueState: inout DateValueState) {
    dateValueState.relativePreset = preset
    switch preset {
    case .custom:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        syncRelativeSelectedDate(&dateValueState)
    case .today:
        dateValueState.mode = .today
        dateValueState.selectedDate = DateNormalizerUtils.normalizedDay(Date())
    case .yesterday:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        dateValueState.relativeAmount = 1
        dateValueState.relativeUnit = .day
        syncRelativeSelectedDate(&dateValueState)
    case .daysAgo7:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        dateValueState.relativeAmount = 7
        dateValueState.relativeUnit = .day
        syncRelativeSelectedDate(&dateValueState)
    case .daysAgo30:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        dateValueState.relativeAmount = 30
        dateValueState.relativeUnit = .day
        syncRelativeSelectedDate(&dateValueState)
    case .monthsAgo3:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        dateValueState.relativeAmount = 3
        dateValueState.relativeUnit = .month
        syncRelativeSelectedDate(&dateValueState)
    case .yearAgo1:
        dateValueState.mode = .relative
        dateValueState.relativeDirection = .past
        dateValueState.relativeAmount = 1
        dateValueState.relativeUnit = .year
        syncRelativeSelectedDate(&dateValueState)
    }
}

func syncRelativeSelectedDate(_ dateValueState: inout DateValueState) {
    let now = DateNormalizerUtils.normalizedDay(Date())
    let literal = RelativeDateConditionLiteral(
        direction: dateValueState.relativeDirection,
        amount: dateValueState.relativeAmount,
        unit: dateValueState.relativeUnit,
        anchorDateLiteral: DateNormalizerUtils.formatDateOnly(now),
    )
    dateValueState.selectedDate = literal.resolve(now: now) ?? now
}

func prepareDateValueState(
    values: [String],
    contract: Condition.ValueContract?,
) -> DateValueState? {
    guard contract?.input == .singleDate
    else {
        return nil
    }

    let now = DateNormalizerUtils.normalizedDay(Date())
    let rawValue = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if let literal = RelativeDateConditionLiteral(canonicalLiteral: rawValue) {
        return DateValueState(
            mode: .relative,
            selectedDate: literal.resolve(now: now) ?? now,
            relativeDirection: literal.direction,
            relativeAmount: literal.amount,
            relativeUnit: literal.unit,
        )
    }

    if let parsed = ConditionValueNormalizer.parseDate(rawValue) {
        return DateValueState(
            mode: isToday(parsed) ? .today : .absolute,
            selectedDate: parsed,
            relativeDirection: .past,
            relativeAmount: 1,
            relativeUnit: .day,
        )
    }

    return DateValueState(
        mode: .absolute,
        selectedDate: now,
        relativeDirection: .past,
        relativeAmount: 1,
        relativeUnit: .day,
    )
}

func commitSemanticDateIfNeeded(
    state: inout ValuePickerFeature.State,
) -> Effect<ValuePickerFeature.Action>? {
    guard isSingleDateEditing(state),
          let dateValueState = state.dateValueState
    else {
        return nil
    }

    let rawValue: String
    let displayValue: String

    switch dateValueState.mode {
    case .absolute:
        rawValue = DateNormalizerUtils.formatDateOnly(dateValueState.selectedDate)
        displayValue = rawValue

    case .relative:
        let anchorDateLiteral = DateNormalizerUtils.formatDateOnly(Date())
        guard let encoded = RelativeDateConditionLiteral.encode(
            direction: dateValueState.relativeDirection,
            amount: dateValueState.relativeAmount,
            unit: dateValueState.relativeUnit,
            anchorDateLiteral: anchorDateLiteral,
        ) else {
            state.errorMessage = "Enter a valid date."
            return .none
        }
        rawValue = encoded
        displayValue = dateValueState.displayText()

    case .today:
        rawValue = DateNormalizerUtils.formatDateOnly(Date())
        displayValue = "Today"
    }

    state.errorMessage = nil
    return .send(
        .commitResult(
            values: [rawValue],
            displayValues: [displayValue],
            selectedUnitCode: nil,
        ),
    )
}

func isSingleDateEditing(_ state: ValuePickerFeature.State) -> Bool {
    if case .singleDate? = state.valueContract?.input {
        true
    } else {
        false
    }
}

func isToday(_ date: Date) -> Bool {
    DateNormalizerUtils.formatDateOnly(date) == DateNormalizerUtils.formatDateOnly(Date())
}

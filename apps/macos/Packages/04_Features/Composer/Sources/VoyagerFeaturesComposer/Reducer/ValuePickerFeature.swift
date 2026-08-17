import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesTag
import VoyagerShared

@Reducer
public struct ValuePickerFeature {
    public typealias State = ValuePickerState
    public typealias Action = ValuePickerAction

    @Dependency(\.finderFavoritesTagClient)
    var finderFavoritesTagClient

    public init() {}

    private static let finderTagPropertyKey = "tag_names"

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                if !isPresented {
                    resetValuePickerState(state: &state)
                }
                return .none

            case let .prepare(payload):
                state.condition = payload.condition
                state.tokenInput = ""
                state.finderTagListState = payload.condition.property.key == Self.finderTagPropertyKey
                    ?
                    .init(options: ConditionTagSuggestions
                        .deduplicatedTagsByName(finderFavoritesTagClient.favoriteTags()))
                    : nil
                state.errorMessage = nil
                state.editingIndex = payload.editingIndex

                let tokenMode = if case .listText? = state.valueContract?.input {
                    true
                } else {
                    false
                }

                state.values = prepareValueInputs(
                    contract: state.valueContract,
                    existingValues: payload.existingValues,
                    currentValues: state.values,
                    tokenMode: tokenMode,
                )

                state.unitContract = payload.condition.property.unitContract
                if let unitContract = state.unitContract, !tokenMode {
                    let unitValueState = UnitValueState(
                        contract: unitContract,
                        preferredUnitCode: payload.preferredUnitCode,
                    )
                    let selectedUnitCode = unitValueState.selectedUnitCode

                    state.unitValueState = unitValueState

                    if let existingDisplayValues = payload.existingDisplayValues {
                        state.values = prepareValueInputs(
                            contract: state.valueContract,
                            existingValues: existingDisplayValues,
                            currentValues: state.values,
                            tokenMode: false,
                        )
                    } else {
                        state.values = state.values.map { raw in
                            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return "" }
                            return ConditionUnitConverter.fromCanonical(
                                canonicalText: trimmed,
                                to: selectedUnitCode,
                                contract: unitContract,
                            ) ?? trimmed
                        }
                    }
                } else {
                    state.unitValueState = nil
                }

                state.dateValueState = prepareDateValueState(
                    values: state.values,
                    contract: state.valueContract,
                )

                state.isPresented = true
                return .none

            case let .setValue(index, text):
                ensureEditableValues(state: &state)
                guard state.values.indices.contains(index) else { return .none }
                state.values[index] = text
                if index == 0,
                   isSingleDateEditing(state),
                   let parsed = ConditionValueNormalizer.parseDate(text)
                {
                    state.dateValueState?.selectedDate = parsed
                    state.dateValueState?.mode = isToday(parsed) ? .today : .absolute
                }
                return .none

            case let .setDateMode(mode):
                guard var dateValueState = state.dateValueState else { return .none }
                dateValueState.mode = mode
                switch mode {
                case .absolute:
                    break
                case .relative:
                    dateValueState.relativePreset = .custom
                    syncRelativeSelectedDate(&dateValueState)
                case .today:
                    dateValueState.relativePreset = .today
                    dateValueState.selectedDate = DateNormalizerUtils.normalizedDay(Date())
                }
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .setDateSelection(date):
                guard var dateValueState = state.dateValueState else { return .none }
                if dateValueState.mode == .relative {
                    syncRelativeSelectedDate(&dateValueState)
                    state.dateValueState = dateValueState
                    state.errorMessage = nil
                    return .none
                }
                let normalized = DateNormalizerUtils.normalizedDay(date)
                dateValueState.selectedDate = normalized
                dateValueState.mode = isToday(normalized) ? .today : .absolute
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .setRelativeDateDirection(direction):
                guard var dateValueState = state.dateValueState else { return .none }
                dateValueState.relativeDirection = direction
                dateValueState.mode = .relative
                dateValueState.relativePreset = .custom
                syncRelativeSelectedDate(&dateValueState)
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .setRelativeDateAmount(amount):
                guard var dateValueState = state.dateValueState else { return .none }
                dateValueState.relativeAmount = max(1, amount)
                dateValueState.mode = .relative
                dateValueState.relativePreset = .custom
                syncRelativeSelectedDate(&dateValueState)
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .setRelativeDateUnit(unit):
                guard var dateValueState = state.dateValueState else { return .none }
                dateValueState.relativeUnit = unit
                dateValueState.mode = .relative
                dateValueState.relativePreset = .custom
                syncRelativeSelectedDate(&dateValueState)
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .setRelativeDatePreset(preset):
                guard var dateValueState = state.dateValueState else { return .none }
                applyRelativePreset(preset, to: &dateValueState)
                state.dateValueState = dateValueState
                state.errorMessage = nil
                return .none

            case let .selectUnit(unitCode):
                guard state.unitContract != nil,
                      let unitValueState = state.unitValueState,
                      unitValueState.availableUnitCodes.contains(unitCode)
                else {
                    return .none
                }
                state.unitValueState?.selectedUnitCode = unitCode
                state.errorMessage = nil
                return .none

            case let .setTokenInput(text):
                state.tokenInput = text
                return .none

            case let .appendToken(rawToken):
                let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else {
                    state.tokenInput = ""
                    return .none
                }

                let normalized = ConditionTagSuggestions.normalizedTokenKey(token)
                let existing = Set(state.values.map(ConditionTagSuggestions.normalizedTokenKey))
                guard !existing.contains(normalized) else {
                    state.tokenInput = ""
                    return .none
                }

                state.values.append(token)
                state.values = ConditionValueNormalizer.deduplicatedTokenValues(state.values)
                state.tokenInput = ""
                state.errorMessage = nil
                return .none

            case let .removeToken(rawToken):
                let normalized = ConditionTagSuggestions.normalizedTokenKey(rawToken)
                state.values.removeAll { ConditionTagSuggestions.normalizedTokenKey($0) == normalized }
                state.errorMessage = nil
                return .none

            case .commit:
                guard state.condition?.operation != nil
                else {
                    return .none
                }

                if let dateCommitEffect = commitSemanticDateIfNeeded(state: &state) {
                    return dateCommitEffect
                }

                let tokenMode = if case .listText? = state.valueContract?.input {
                    true
                } else {
                    false
                }
                let expected = requiredValueInputCount(
                    contract: state.valueContract,
                    currentValues: state.values,
                )
                var displayValues = state.values
                if tokenMode {
                    let token = state.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !token.isEmpty {
                        let normalized = ConditionTagSuggestions.normalizedTokenKey(token)
                        let existing = Set(displayValues.map(ConditionTagSuggestions.normalizedTokenKey))
                        if !existing.contains(normalized) {
                            displayValues.append(token)
                        }
                    }
                    displayValues = ConditionValueNormalizer.deduplicatedTokenValues(displayValues)
                    state.tokenInput = ""
                }

                if expected > 0, displayValues.count < expected {
                    displayValues.append(contentsOf: Array(repeating: "", count: expected - displayValues.count))
                }

                let rawValues: [String]
                let selectedUnitCode = state.unitValueState?.selectedUnitCode
                if let unitContract = state.unitContract, !tokenMode, let selectedUnitCode {
                    let canonicalValues = displayValues.compactMap {
                        ConditionUnitConverter.toCanonical(
                            displayValueText: $0,
                            from: selectedUnitCode,
                            contract: unitContract,
                        )
                    }
                    guard canonicalValues.count == displayValues.count else {
                        state.errorMessage = "Enter a valid number."
                        return .none
                    }
                    rawValues = canonicalValues
                    displayValues = displayValues
                } else {
                    rawValues = displayValues
                }

                guard let contract = state.valueContract else { return .none }
                let result = ConditionValueNormalizer.normalize(
                    contract: contract,
                    rawValues: rawValues,
                    editingIndex: state.editingIndex,
                )

                if let error = result.errorMessage {
                    state.errorMessage = error
                    result.resetIndices
                        .filter { state.values.indices.contains($0) }
                        .forEach { state.values[$0] = "" }
                    if expected > 0, state.values.count < expected {
                        state.values.append(contentsOf: Array(repeating: "", count: expected - state.values.count))
                    }
                    return .none
                }

                state.errorMessage = nil
                guard let committedValues = result.values else {
                    return .none
                }
                if tokenMode {
                    state.values = ConditionValueNormalizer.deduplicatedTokenValues(displayValues)
                }
                return .send(
                    .commitResult(
                        values: committedValues,
                        displayValues: displayValues,
                        selectedUnitCode: state.unitValueState?.selectedUnitCode,
                    ),
                )

            case .commitResult:
                return .none
            }
        }
    }
}

private func resetValuePickerState(state: inout ValuePickerState) {
    state.condition = nil
    state.values = [""]
    state.unitValueState = nil
    state.unitContract = nil
    state.tokenInput = ""
    state.finderTagListState = nil
    state.errorMessage = nil
    state.editingIndex = nil
    state.dateValueState = nil
}

private func ensureEditableValues(state: inout ValuePickerState) {
    let count = max(
        requiredValueInputCount(contract: state.valueContract, currentValues: state.values),
        1,
    )
    if state.values.count < count {
        state.values = Array(repeating: "", count: count)
    }
}

private func requiredValueInputCount(
    contract: Condition.ValueContract?,
    currentValues: [String],
) -> Int {
    switch contract?.count {
    case let .fixed(count):
        count
    case .multiple:
        max(currentValues.count, 1)
    case nil:
        0
    }
}

private func prepareValueInputs(
    contract: Condition.ValueContract?,
    existingValues: [String]?,
    currentValues: [String],
    tokenMode: Bool,
) -> [String] {
    let minimumCount: Int
    switch contract?.count {
    case let .fixed(count):
        minimumCount = count
    case .multiple:
        minimumCount = 1
    case nil:
        return []
    }
    guard minimumCount > 0 else { return [] }

    if let existingValues {
        let trimmed = existingValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalized = tokenMode ? ConditionValueNormalizer.deduplicatedTokenValues(trimmed) : trimmed
        let effectiveCount = max(minimumCount, normalized.count)
        var values = Array(normalized.prefix(effectiveCount))
        if values.count < effectiveCount {
            values.append(contentsOf: Array(repeating: "", count: effectiveCount - values.count))
        }
        return values
    }

    if minimumCount == 1 {
        return [currentValues.first ?? ""]
    }

    return Array(repeating: "", count: minimumCount)
}

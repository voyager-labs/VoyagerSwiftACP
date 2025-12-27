import ComposableArchitecture
import Foundation

struct Condition: Equatable, Identifiable, Hashable {
    var id: String { propertyKey }
    var propertyKey: String
    var propertyLabel: String
    var propertyType: String
    var operatorCode: String?
    var operatorLabel: String?
    var operatorValueArity: Int?
    var valueType: ValueType = .unknown
    var values: [String]?
}

struct FilterSnapshot: Equatable {
    let scopes: [String]
    let conditions: [Condition]
}

// swiftlint:disable type_body_length
@Reducer
struct ComposerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var text: String = ""
        var scopes: [String] = []
        var conditions: [Condition] = []
        var propertyPicker: ConditionPropertyPickerFeature.State = .init()
        var operatorPicker: OperatorPickerFeature.State = .init()
        var valuePicker: ValuePickerFeature.State = .init()
        var history: [FilterSnapshot] = []
        var redoHistory: [FilterSnapshot] = []

        var canUndo: Bool { !history.isEmpty }
        var canRedo: Bool { !redoHistory.isEmpty }

        mutating func pushHistory() {
            history.append(FilterSnapshot(scopes: scopes, conditions: conditions))
            if history.count > 100 {
                history.removeFirst(history.count - 100)
            }
            redoHistory.removeAll()
        }

        mutating func clearHistory() {
            history.removeAll()
            redoHistory.removeAll()
        }
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case setText(String)
        case addScope(path: String)
        case removeScope(path: String)
        case updateScope(oldPath: String, newPath: String)
        case addCondition(property: MDItemProperty)
        case removeCondition(propertyKey: String)
        case setOperator(propertyKey: String, option: OperatorOption)
        case setValue(propertyKey: String, values: [String])
        case replaceConditionProperty(originalKey: String, property: MDItemProperty)
        case undo
        case redo
        case propertyPicker(ConditionPropertyPickerFeature.Action)
        case operatorPicker(OperatorPickerFeature.Action)
        case valuePicker(ValuePickerFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.propertyPicker, action: \.propertyPicker) {
            ConditionPropertyPickerFeature()
        }
        Scope(state: \.operatorPicker, action: \.operatorPicker) {
            OperatorPickerFeature()
        }
        Scope(state: \.valuePicker, action: \.valuePicker) {
            ValuePickerFeature()
        }

        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented
                return .none

            case let .setText(text):
                state.text = text
                return .none

            case let .addScope(path):
                guard !state.scopes.contains(path) else { return .none }
                state.pushHistory()
                state.scopes.append(path)
                return .none

            case let .removeScope(path):
                if state.scopes.contains(path) {
                    state.pushHistory()
                    state.scopes.removeAll { $0 == path }
                }
                return .none

            case let .updateScope(oldPath, newPath):
                if let index = state.scopes.firstIndex(of: oldPath), oldPath != newPath {
                    state.pushHistory()
                    state.scopes[index] = newPath
                }
                return .none

            case let .addCondition(property):
                if state.conditions.contains(where: { $0.propertyKey == property.key }) {
                    state.propertyPicker.duplicateMessage = "\"\(property.label)\" is already added."
                    return .none
                }

                state.pushHistory()
                let condition = Condition(
                    propertyKey: property.key,
                    propertyLabel: property.label,
                    propertyType: property.type,
                    operatorCode: nil,
                    operatorLabel: nil,
                    operatorValueArity: nil,
                    valueType: valueType(for: property.type),
                    values: nil,
                )
                state.conditions.append(condition)
                state.propertyPicker.duplicateMessage = nil
                state.propertyPicker.isPresented = false
                return .none

            case let .removeCondition(propertyKey):
                if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions.removeAll { $0.propertyKey == propertyKey }
                }
                return .none

            case let .setOperator(propertyKey, option):
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].operatorCode = option.code
                    state.conditions[idx].operatorLabel = option.label
                    state.conditions[idx].operatorValueArity = option.valueArity
                    state.conditions[idx].valueType = option
                        .valueType ?? valueType(for: state.conditions[idx].propertyType)
                    state.conditions[idx].values = nil
                    if state.valuePicker.propertyKey == propertyKey {
                        state.valuePicker.isPresented = false
                        state.valuePicker.propertyKey = nil
                        state.valuePicker.operatorOption = nil
                        state.valuePicker.values = Array(repeating: "", count: option.valueArity)
                        state.valuePicker.errorMessage = nil
                    }
                }
                return .none

            case let .replaceConditionProperty(originalKey, property):
                guard let idx = state.conditions.firstIndex(where: { $0.propertyKey == originalKey }) else {
                    state.propertyPicker.editingConditionKey = nil
                    state.propertyPicker.isPresented = false
                    return .none
                }

                // 중복 방지: 다른 조건에 동일 key가 이미 있으면 안내 후 아무 변화 없이 종료
                if let dupIndex = state.conditions.firstIndex(where: { $0.propertyKey == property.key }),
                   dupIndex != idx
                {
                    state.propertyPicker.duplicateMessage = "\"\(property.label)\" is already added."
                    return .none
                }

                state.pushHistory()
                state.conditions[idx].propertyKey = property.key
                state.conditions[idx].propertyLabel = property.label
                state.conditions[idx].propertyType = property.type
                state.conditions[idx].operatorCode = nil
                state.conditions[idx].operatorLabel = nil
                state.conditions[idx].operatorValueArity = nil
                state.conditions[idx].valueType = valueType(for: property.type)
                state.conditions[idx].values = nil
                state.propertyPicker.editingConditionKey = nil
                state.propertyPicker.isPresented = false
                state.propertyPicker.duplicateMessage = nil
                return .none

            case .undo:
                guard let previous = state.history.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.redoHistory.append(current)
                state.scopes = previous.scopes
                state.conditions = previous.conditions
                return .none

            case .redo:
                guard let next = state.redoHistory.popLast() else { return .none }
                let current = FilterSnapshot(scopes: state.scopes, conditions: state.conditions)
                state.history.append(current)
                state.scopes = next.scopes
                state.conditions = next.conditions
                return .none

            case let .propertyPicker(.propertyTapped(property)):
                if let editingKey = state.propertyPicker.editingConditionKey {
                    return .send(.replaceConditionProperty(originalKey: editingKey, property: property))
                } else {
                    return .send(.addCondition(property: property))
                }

            case let .propertyPicker(.setPresented(isPresented)):
                if isPresented {
                    state.propertyPicker.existingKeys = Set(state.conditions.map(\.propertyKey))
                } else {
                    state.propertyPicker.existingKeys = []
                }
                return .none

            case let .propertyPicker(.startEditing(conditionKey)):
                state.propertyPicker.existingKeys = Set(
                    state.conditions
                        .map(\.propertyKey)
                        .filter { $0 != conditionKey },
                )
                return .none

            case .propertyPicker:
                return .none

            case let .operatorPicker(.setPresented(isPresented)):
                state.operatorPicker.isPresented = isPresented
                if !isPresented {
                    state.operatorPicker.propertyKey = nil
                    state.operatorPicker.options = []
                }
                return .none

            case let .operatorPicker(.prepare(propertyKey, options)):
                state.operatorPicker.propertyKey = propertyKey
                state.operatorPicker.options = options
                state.operatorPicker.isPresented = true
                return .none

            case let .operatorPicker(.select(option)):
                guard let propertyKey = state.operatorPicker.propertyKey else {
                    return .none
                }
                return .send(.setOperator(propertyKey: propertyKey, option: option))

            case .operatorPicker:
                return .none

            case let .valuePicker(.setPresented(isPresented)):
                state.valuePicker.isPresented = isPresented
                if !isPresented {
                    state.valuePicker.propertyKey = nil
                    state.valuePicker.operatorOption = nil
                    if state.valuePicker.valueArity > 0 {
                        state.valuePicker.values = Array(repeating: "", count: state.valuePicker.valueArity)
                    }
                    state.valuePicker.errorMessage = nil
                }
                return .none

            case let .valuePicker(.prepare(payload)):
                state.valuePicker.propertyKey = payload.propertyKey
                state.valuePicker.operatorOption = payload.operatorOption
                state.valuePicker.valueType = payload.valueType
                state.valuePicker.valueArity = max(0, payload.operatorOption.valueArity)
                state.valuePicker.editingIndex = payload.editingIndex

                if state.valuePicker.valueArity == 0 {
                    state.valuePicker.values = []
                } else if let existingValues = payload.existingValues {
                    let trimmed = existingValues.map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    state.valuePicker.values = Array(trimmed.prefix(state.valuePicker.valueArity))
                    if state.valuePicker.values.count < state.valuePicker.valueArity {
                        state.valuePicker.values.append(contentsOf: Array(
                            repeating: "",
                            count: state.valuePicker.valueArity - state.valuePicker.values.count,
                        ))
                    }
                } else if state.valuePicker.valueArity == 1 {
                    state.valuePicker.values = [""]
                } else {
                    state.valuePicker.values = Array(repeating: "", count: state.valuePicker.valueArity)
                }
                state.valuePicker.isPresented = true
                return .none

            case let .valuePicker(.setValue(index, text)):
                if state.valuePicker.values.indices.contains(index) {
                    state.valuePicker.values[index] = text
                }
                return .none

            case .valuePicker(.commit):
                guard let propertyKey = state.valuePicker.propertyKey else { return .none }

                if state.valuePicker.values.isEmpty, state.valuePicker.valueArity > 0 {
                    state.valuePicker.errorMessage = "Value is required."
                    return .none
                }

                if state.valuePicker.values.count < state.valuePicker.valueArity {
                    state.valuePicker.values.append(
                        contentsOf: Array(
                            repeating: "",
                            count: state.valuePicker.valueArity - state.valuePicker.values.count,
                        ),
                    )
                }

                let trimmed = state.valuePicker.values
                    .prefix(max(state.valuePicker.valueArity, 0))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if trimmed.contains(where: \.isEmpty) {
                    state.valuePicker.errorMessage = "Value is required."
                    return .none
                }

                if state.valuePicker.valueType == .number {
                    let numbers = trimmed.compactMap { Double($0) }
                    guard numbers.count == trimmed.count else {
                        state.valuePicker.errorMessage = "Enter valid numbers."
                        // 숫자 변환 실패 시 잘못된 인덱스만 비우기
                        for (idx, value) in trimmed.enumerated() {
                            if Double(value) == nil, state.valuePicker.values.indices.contains(idx) {
                                state.valuePicker.values[idx] = ""
                            }
                        }
                        return .none
                    }
                    if numbers.count >= 2, numbers[0] > numbers[1] {
                        state.valuePicker.errorMessage = "From must be ≤ To."
                        if let editIdx = state.valuePicker.editingIndex,
                           state.valuePicker.values.indices.contains(editIdx)
                        {
                            state.valuePicker.values[editIdx] = ""
                        } else if state.valuePicker.values.indices.contains(0) {
                            state.valuePicker.values[0] = ""
                        }
                        return .none
                    }
                } else if state.valuePicker.valueType == .date {
                    let dates = trimmed.compactMap { ValuePickerFeature.parseDate($0) }
                    guard dates.count == trimmed.count else {
                        state.valuePicker.errorMessage = "Enter valid date."
                        for (idx, value) in trimmed.enumerated() {
                            if ValuePickerFeature.parseDate(value) == nil,
                               state.valuePicker.values.indices.contains(idx)
                            {
                                state.valuePicker.values[idx] = ""
                            }
                        }
                        return .none
                    }
                    if dates.count >= 2, dates[0] > dates[1] {
                        state.valuePicker.errorMessage = "From must be ≤ To."
                        if let editIdx = state.valuePicker.editingIndex,
                           state.valuePicker.values.indices.contains(editIdx)
                        {
                            state.valuePicker.values[editIdx] = ""
                        } else if state.valuePicker.values.indices.contains(0) {
                            state.valuePicker.values[0] = ""
                        }
                        return .none
                    }
                }

                state.valuePicker.errorMessage = nil
                return .send(.setValue(propertyKey: propertyKey, values: trimmed))

            case .valuePicker:
                return .none

            case let .setValue(propertyKey, values):
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].values = values
                }
                state.valuePicker.isPresented = false
                state.valuePicker.propertyKey = nil
                state.valuePicker.operatorOption = nil
                state.valuePicker.errorMessage = nil
                state.valuePicker.editingIndex = nil
                return .none
            }
        }
    }
}

// swiftlint:enable type_body_length

private func valueType(for propertyType: String) -> ValueType {
    switch propertyType {
    case "string":
        .string
    case "number":
        .number
    case "date":
        .date
    case "boolean":
        .boolean
    case "array":
        .array
    default:
        .unknown
    }
}

import ComposableArchitecture
import Foundation

struct Condition: Equatable, Identifiable, Hashable {
    var id: String { propertyKey }
    var propertyKey: String
    var propertyLabel: String
    var propertyType: String
    var operatorCode: String?
    var operatorLabel: String?
    // TODO(voy-95): value 추가 예정
}

struct FilterSnapshot: Equatable {
    let scopes: [String]
    let conditions: [Condition]
}

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
        case setOperator(propertyKey: String, code: String, label: String)
        case replaceConditionProperty(originalKey: String, property: MDItemProperty)
        case undo
        case redo
        case propertyPicker(ConditionPropertyPickerFeature.Action)
        case operatorPicker(OperatorPickerFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.propertyPicker, action: \.propertyPicker) {
            ConditionPropertyPickerFeature()
        }
        Scope(state: \.operatorPicker, action: \.operatorPicker) {
            OperatorPickerFeature()
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

            case let .setOperator(propertyKey, code, label):
                if let idx = state.conditions.firstIndex(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions[idx].operatorCode = code
                    state.conditions[idx].operatorLabel = label
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
                return .send(.setOperator(propertyKey: propertyKey, code: option.code, label: option.label))

            case .operatorPicker:
                return .none
            }
        }
    }
}

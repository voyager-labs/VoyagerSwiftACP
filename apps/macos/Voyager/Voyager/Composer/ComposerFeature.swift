import ComposableArchitecture
import Foundation

struct Condition: Equatable, Identifiable {
    var id: String { propertyKey }
    let propertyKey: String
    let propertyLabel: String
    // TODO(voy-95): operator, value 추가 예정
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
        case undo
        case redo
        case propertyPicker(ConditionPropertyPickerFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.propertyPicker, action: \.propertyPicker) {
            ConditionPropertyPickerFeature()
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
                if !state.conditions.contains(where: { $0.propertyKey == property.key }) {
                    state.pushHistory()
                    let condition = Condition(
                        propertyKey: property.key,
                        propertyLabel: property.label,
                    )
                    state.conditions.append(condition)
                }
                state.propertyPicker.isPresented = false
                return .none

            case let .removeCondition(propertyKey):
                if state.conditions.contains(where: { $0.propertyKey == propertyKey }) {
                    state.pushHistory()
                    state.conditions.removeAll { $0.propertyKey == propertyKey }
                }
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
                return .send(.addCondition(property: property))

            case .propertyPicker:
                return .none
            }
        }
    }
}

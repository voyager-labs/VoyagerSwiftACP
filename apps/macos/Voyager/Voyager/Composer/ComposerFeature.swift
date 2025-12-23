import ComposableArchitecture
import Foundation

struct Condition: Equatable, Identifiable {
    var id: String { propertyKey }
    let propertyKey: String
    let propertyLabel: String
    // TODO(voy-95): operator, value 추가 예정
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
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case setText(String)
        case addScope(path: String)
        case removeScope(path: String)
        case updateScope(oldPath: String, newPath: String)
        case addCondition(property: MDItemProperty)
        case removeCondition(propertyKey: String)
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
                if !isPresented {
                    state.text = ""
                }
                return .none

            case let .setText(text):
                state.text = text
                return .none

            case let .addScope(path):
                if !state.scopes.contains(path) {
                    state.scopes.append(path)
                }
                return .none

            case let .removeScope(path):
                state.scopes.removeAll { $0 == path }
                return .none

            case let .updateScope(oldPath, newPath):
                if let index = state.scopes.firstIndex(of: oldPath) {
                    state.scopes[index] = newPath
                }
                return .none

            case let .addCondition(property):
                if !state.conditions.contains(where: { $0.propertyKey == property.key }) {
                    let condition = Condition(
                        propertyKey: property.key,
                        propertyLabel: property.label,
                    )
                    state.conditions.append(condition)
                }
                state.propertyPicker.isPresented = false
                return .none

            case let .removeCondition(propertyKey):
                state.conditions.removeAll { $0.propertyKey == propertyKey }
                return .none

            case let .propertyPicker(.propertyTapped(property)):
                return .send(.addCondition(property: property))

            case .propertyPicker:
                return .none
            }
        }
    }
}

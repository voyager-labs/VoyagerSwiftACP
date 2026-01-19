import ComposableArchitecture
import Foundation

@Reducer
struct ConditionPropertyPickerFeature {
    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var properties: [SystemProperty] = {
            ConditionMappingUtils.allProperties.map { info in
                SystemProperty(
                    key: info.key,
                    label: info.label,
                    category: info.category,
                    type: info.type,
                    isDefault: info.isDefault,
                )
            }
        }()

        var searchText: String = ""
        var mode: Mode = .root
        var selectedCategory: String?
        var editingConditionKey: String?
        var duplicateMessage: String?
        var existingKeys: Set<String> = []
    }

    enum Mode: Equatable {
        case root
        case category(String)
    }

    enum Action: Sendable {
        case setPresented(Bool)
        case onAppear
        case searchTextChanged(String)
        case categoryTapped(String)
        case backFromCategory
        case propertyTapped(SystemProperty)
        case startEditing(String)
        case clearDuplicateMessage
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .setPresented(isPresented):
                state.isPresented = isPresented

                if !isPresented {
                    state.mode = .root
                    state.selectedCategory = nil
                    state.searchText = ""
                    state.editingConditionKey = nil
                    state.duplicateMessage = nil
                    state.existingKeys = []
                }
                return .none

            case .onAppear:
                return .none

            case let .searchTextChanged(text):
                state.searchText = text
                return .none

            case let .categoryTapped(category):
                state.mode = .category(category)
                state.selectedCategory = category
                return .none

            case .backFromCategory:
                state.mode = .root
                state.selectedCategory = nil
                return .none

            case .propertyTapped:
                return .none

            case let .startEditing(conditionKey):
                state.editingConditionKey = conditionKey
                state.isPresented = true
                state.mode = .root
                state.selectedCategory = nil
                state.searchText = ""
                state.duplicateMessage = nil
                return .none

            case .clearDuplicateMessage:
                state.duplicateMessage = nil
                return .none
            }
        }
    }
}

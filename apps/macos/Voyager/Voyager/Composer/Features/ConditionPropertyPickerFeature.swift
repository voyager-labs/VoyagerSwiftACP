import ComposableArchitecture
import Foundation

@Reducer
struct ConditionPropertyPickerFeature {
    @Dependency(\.registryClient)
    var registryClient

    @ObservableState
    struct State: Equatable {
        var isPresented: Bool = false
        var properties: [String] = []
        var propertyLabels: [String: String] = [:]
        var propertyCategories: [String: String] = [:]
        var propertyDefaults: Set<String> = []

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
        case propertyTapped(String)
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
                let entries = registryClient.allProperties()
                state.properties = entries.map(\.key)
                state.propertyLabels = Dictionary(
                    uniqueKeysWithValues: entries.map { ($0.key, $0.definition.uiLabel ?? $0.key) },
                )
                state.propertyCategories = Dictionary(
                    uniqueKeysWithValues: entries.map { ($0.key, $0.category) },
                )
                state.propertyDefaults = Set(
                    entries
                        .filter { $0.definition.uiPinned ?? false }
                        .map(\.key),
                )
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

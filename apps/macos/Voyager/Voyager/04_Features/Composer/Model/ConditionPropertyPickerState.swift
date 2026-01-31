import ComposableArchitecture
import Foundation

@ObservableState
struct ConditionPropertyPickerState: Equatable {
    var isPresented: Bool = false
    var properties: [String] = []
    var propertyLabels: [String: String] = [:]
    var propertyCategories: [String: String] = [:]
    var propertyTypes: [String: String] = [:]
    var propertyDefaults: Set<String> = []

    var searchText: String = ""
    var mode: ConditionPropertyPickerMode = .root
    var selectedCategory: String?
    var editingConditionKey: String?
    var duplicateMessage: String?
    var existingKeys: Set<String> = []
}

enum ConditionPropertyPickerMode: Equatable {
    case root
    case category(String)
}

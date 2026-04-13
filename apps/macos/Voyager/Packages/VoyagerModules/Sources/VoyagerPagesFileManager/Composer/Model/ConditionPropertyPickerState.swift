import ComposableArchitecture
import Foundation

@ObservableState
public struct ConditionPropertyPickerState: Equatable {
    public var isPresented: Bool = false
    public var properties: [String] = []
    public var propertyLabels: [String: String] = [:]
    public var propertyCategories: [String: String] = [:]
    public var propertyTypes: [String: String] = [:]
    public var propertyDefaults: Set<String> = []

    public var searchText: String = ""
    public var mode: ConditionPropertyPickerMode = .root
    public var selectedCategory: String?
    public var editingConditionKey: String?
    public var duplicateMessage: String?
    public var existingKeys: Set<String> = []
}

public enum ConditionPropertyPickerMode: Equatable {
    case root
    case category(String)
}

import ComposableArchitecture

@CasePathable
enum ComposerAction: CasePathable, Sendable {
    case setPresented(Bool)
    case setText(String)
    case focusQueryField

    case addScope(path: String)
    case removeScope(path: String)
    case updateScope(oldPath: String, newPath: String)

    case addCondition(propertyKey: String)
    case removeCondition(propertyKey: String)
    case replaceConditionProperty(originalKey: String, propertyKey: String)
    case setOperator(propertyKey: String, operatorCode: String)
    case setValue(propertyKey: String, values: [String])

    case clearAll
    case submit
    case applyFilters
    case cancelSearch
    case cancelFilters

    case saveCollection
    case saveCollectionAs

    case undo
    case redo

    case collection(CollectionFeature.Action)
    case propertyPicker(ConditionPropertyPickerFeature.Action)
    case operatorPicker(OperatorPickerFeature.Action)
    case valuePicker(ValuePickerFeature.Action)

    case searchResponse(Result<SearchResponsePayload, Error>)
    case filtersResponse(Result<SearchResponsePayload, Error>)
    case searchListApplied
}

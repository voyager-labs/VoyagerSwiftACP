import ComposableArchitecture
import Foundation
import VoyagerShared

@CasePathable
enum ComposerAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    case collection(CollectionFeature.Action)
    case propertyPicker(ConditionPropertyPickerFeature.Action)
    case operatorPicker(OperatorPickerFeature.Action)
    case valuePicker(ValuePickerFeature.Action)

    @CasePathable
    enum View: Sendable {
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
        case setDisplayUnit(propertyKey: String, unitCode: String)
        case clearAll
        case submit
        case applyFilters
        case cancelSearch
        case cancelFilters
        case saveCollection
        case saveCollectionAs
        case undo
        case redo
    }

    @CasePathable
    enum Internal: Sendable {
        case searchResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case filtersResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case dismissTransientFeedback(UUID)
        case searchListApplied
    }

    @CasePathable
    enum Delegate: Sendable {}
}

extension ComposerAction {
    static func setPresented(_ isPresented: Bool) -> Self { .view(.setPresented(isPresented)) }
    static func setText(_ text: String) -> Self { .view(.setText(text)) }
    static var focusQueryField: Self { .view(.focusQueryField) }
    static func addScope(path: String) -> Self { .view(.addScope(path: path)) }
    static func removeScope(path: String) -> Self { .view(.removeScope(path: path)) }
    static func updateScope(oldPath: String, newPath: String) -> Self {
        .view(.updateScope(oldPath: oldPath, newPath: newPath))
    }

    static func addCondition(propertyKey: String) -> Self { .view(.addCondition(propertyKey: propertyKey)) }
    static func removeCondition(propertyKey: String) -> Self {
        .view(.removeCondition(propertyKey: propertyKey))
    }

    static func replaceConditionProperty(originalKey: String, propertyKey: String) -> Self {
        .view(.replaceConditionProperty(originalKey: originalKey, propertyKey: propertyKey))
    }

    static func setOperator(propertyKey: String, operatorCode: String) -> Self {
        .view(.setOperator(propertyKey: propertyKey, operatorCode: operatorCode))
    }

    static func setValue(propertyKey: String, values: [String]) -> Self {
        .view(.setValue(propertyKey: propertyKey, values: values))
    }

    static func setDisplayUnit(propertyKey: String, unitCode: String) -> Self {
        .view(.setDisplayUnit(propertyKey: propertyKey, unitCode: unitCode))
    }

    static var clearAll: Self { .view(.clearAll) }
    static var submit: Self { .view(.submit) }
    static var applyFilters: Self { .view(.applyFilters) }
    static var cancelSearch: Self { .view(.cancelSearch) }
    static var cancelFilters: Self { .view(.cancelFilters) }
    static var saveCollection: Self { .view(.saveCollection) }
    static var saveCollectionAs: Self { .view(.saveCollectionAs) }
    static var undo: Self { .view(.undo) }
    static var redo: Self { .view(.redo) }

    static func searchResponse(_ requestID: UUID,
                               _ result: Result<VoyagerShared.SearchResponsePayload, Error>) -> Self
    {
        .internal(.searchResponse(requestID, result))
    }

    static func filtersResponse(_ requestID: UUID,
                                _ result: Result<VoyagerShared.SearchResponsePayload, Error>) -> Self
    {
        .internal(.filtersResponse(requestID, result))
    }

    static func dismissTransientFeedback(id: UUID) -> Self {
        .internal(.dismissTransientFeedback(id))
    }

    static var searchListApplied: Self { .internal(.searchListApplied) }
}

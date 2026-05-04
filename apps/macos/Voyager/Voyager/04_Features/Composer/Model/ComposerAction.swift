import ComposableArchitecture
import Foundation
import VoyagerShared

@CasePathable
enum ComposerAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    case propertyPicker(ConditionPropertyPickerFeature.Action)
    case operatorPicker(OperatorPickerFeature.Action)
    case valuePicker(ValuePickerFeature.Action)

    @CasePathable
    enum View: Sendable {
        case setPresented(Bool)
        case setText(String)
        case focusQueryField
        case scopeEditorOpen(editingPath: String?, favorites: [ScopeFavoriteItem], backHistory: [String])
        case scopeEditorSetPresented(Bool)
        case scopeEditorSetQueryText(String)
        case scopeEditorSetIncludeSubfolders(Bool)
        case candidateScope(CandidateScope)
        case currentScope(CurrentScope)
        case exceptionScope(ExceptionScope)
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
        case scopeFeedbackUndoTapped
        case scopeFeedbackRedoTapped
    }

    @CasePathable
    enum CandidateScope: Sendable {
        case add(path: String)
    }

    @CasePathable
    enum CurrentScope: Sendable {
        case remove(path: String)
        case replace(oldPath: String, newPath: String)
    }

    @CasePathable
    enum ExceptionScope: Sendable {
        case exclude(path: String)
        case restore(path: String)
    }

    @CasePathable
    enum Internal: Sendable {
        case searchResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case filtersResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case scopeEditorSeedCurrentPath(String)
        case scopeEditorSearchResponse(String, Result<[ComposerScopeUtils.DirectoryItem], Error>)
        case dismissTransientFeedback(UUID)
        case searchListApplied
    }

    @CasePathable
    enum Delegate: Sendable {
        case saveRequested(SaveRequestPayload)
        case saveToExisting(SaveRequestPayload, URL)
    }
}

extension ComposerAction {
    static func setPresented(_ isPresented: Bool) -> Self { .view(.setPresented(isPresented)) }
    static func setText(_ text: String) -> Self { .view(.setText(text)) }
    static var focusQueryField: Self { .view(.focusQueryField) }
    static func scopeEditorOpen(editingPath: String?, favorites: [ScopeFavoriteItem], backHistory: [String]) -> Self {
        .view(.scopeEditorOpen(editingPath: editingPath, favorites: favorites, backHistory: backHistory))
    }

    static func scopeEditorSetPresented(_ isPresented: Bool) -> Self { .view(.scopeEditorSetPresented(isPresented)) }
    static func scopeEditorSetQueryText(_ text: String) -> Self { .view(.scopeEditorSetQueryText(text)) }
    static func scopeEditorSetIncludeSubfolders(_ includeSubfolders: Bool)
        -> Self { .view(.scopeEditorSetIncludeSubfolders(includeSubfolders)) }
    static func candidateScope(_ action: CandidateScope) -> Self { .view(.candidateScope(action)) }
    static func currentScope(_ action: CurrentScope) -> Self { .view(.currentScope(action)) }
    static func exceptionScope(_ action: ExceptionScope) -> Self { .view(.exceptionScope(action)) }
    static func addScope(path: String) -> Self { .view(.candidateScope(.add(path: path))) }
    static func removeScope(path: String) -> Self { .view(.currentScope(.remove(path: path))) }
    static func updateScope(oldPath: String, newPath: String) -> Self {
        .view(.currentScope(.replace(oldPath: oldPath, newPath: newPath)))
    }

    static func excludeScope(path: String) -> Self { .view(.exceptionScope(.exclude(path: path))) }
    static func restoreScope(path: String) -> Self { .view(.exceptionScope(.restore(path: path))) }

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
    static var scopeFeedbackUndoTapped: Self { .view(.scopeFeedbackUndoTapped) }
    static var scopeFeedbackRedoTapped: Self { .view(.scopeFeedbackRedoTapped) }

    static func searchResponse(
        _ requestID: UUID,
        _ result: Result<VoyagerShared.SearchResponsePayload, Error>,
    ) -> Self {
        .internal(.searchResponse(requestID, result))
    }

    static func scopeEditorSeedCurrentPath(_ currentPath: String) -> Self {
        .internal(.scopeEditorSeedCurrentPath(currentPath))
    }

    static func scopeEditorSearchResponse(
        _ query: String,
        _ result: Result<[ComposerScopeUtils.DirectoryItem], Error>,
    ) -> Self {
        .internal(.scopeEditorSearchResponse(query, result))
    }

    static func filtersResponse(
        _ requestID: UUID,
        _ result: Result<VoyagerShared.SearchResponsePayload, Error>,
    ) -> Self {
        .internal(.filtersResponse(requestID, result))
    }

    static func dismissTransientFeedback(id: UUID) -> Self {
        .internal(.dismissTransientFeedback(id))
    }

    static var searchListApplied: Self { .internal(.searchListApplied) }
}

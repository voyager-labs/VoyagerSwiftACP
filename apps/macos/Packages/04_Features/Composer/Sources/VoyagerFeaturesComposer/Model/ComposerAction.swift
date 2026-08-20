import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerShared

@CasePathable
public enum ComposerAction: ViewAction, CasePathable, Sendable {
    case view(View)
    case delegate(Delegate)
    case `internal`(Internal)

    case propertyPicker(ConditionPropertyPickerFeature.Action)
    case valuePicker(ValuePickerFeature.Action)
    case conditionEditor(IdentifiedActionOf<ConditionEditorFeature>)

    @CasePathable
    public enum View: Sendable {
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
        case removeCondition(id: UUID)
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
    public enum CandidateScope: Sendable {
        case add(path: String)
    }

    @CasePathable
    public enum CurrentScope: Sendable {
        case remove(path: String)
        case replace(oldPath: String, newPath: String)
    }

    @CasePathable
    public enum ExceptionScope: Sendable {
        case exclude(path: String)
        case restore(path: String)
    }

    @CasePathable
    public enum Internal: Sendable {
        case searchResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case filtersResponse(UUID, Result<VoyagerShared.SearchResponsePayload, Error>)
        case scopeEditorSeedCurrentPath(String)
        case scopeEditorSearchResponse(String, Result<[ComposerScopeUtils.DirectoryItem], Error>)
        case dismissTransientFeedback(UUID)
        case presentTransientFeedback(ComposerTransientFeedback)
        case clearTransientFeedback
        case cleanupCollectionWork
        case searchListApplied
        case applyCollectionDraftRestore(CollectionDraftRestorePayload)
        case applyCollectionNavigationComposer(CollectionNavigationStatePayload)
        case syncCollectionState(
            context: CollectionContext?,
            url: URL?,
            compatibility: CollectionFileCompatibilityMetadata?,
            isCollectionMode: Bool,
        )
        case updateLastFiltersResponse(VoyagerShared.SearchResponsePayload)
        case clearPendingSearchQuery
        case setPendingSearchQuery(String?)
        case setLoadingFilters(Bool)
        case setInitialScope(String)
        case resetComposerAndSync(
            context: CollectionContext?,
            url: URL?,
            compatibility: CollectionFileCompatibilityMetadata?,
            isCollectionMode: Bool,
        )
    }

    @CasePathable
    public enum Delegate: Sendable {
        case saveRequested(SaveRequestPayload)
        case saveToExisting(SaveRequestPayload, URL)
    }

    public static var focusQueryField: Self {
        .view(.focusQueryField)
    }

    public static var clearAll: Self {
        .view(.clearAll)
    }

    public static var submit: Self {
        .view(.submit)
    }

    public static var applyFilters: Self {
        .view(.applyFilters)
    }

    public static var cancelSearch: Self {
        .view(.cancelSearch)
    }

    public static var cancelFilters: Self {
        .view(.cancelFilters)
    }

    public static var saveCollection: Self {
        .view(.saveCollection)
    }

    public static var saveCollectionAs: Self {
        .view(.saveCollectionAs)
    }

    public static var undo: Self {
        .view(.undo)
    }

    public static var redo: Self {
        .view(.redo)
    }

    public static var scopeFeedbackUndoTapped: Self {
        .view(.scopeFeedbackUndoTapped)
    }

    public static var scopeFeedbackRedoTapped: Self {
        .view(.scopeFeedbackRedoTapped)
    }

    public static var searchListApplied: Self {
        .internal(.searchListApplied)
    }

    public static var clearPendingSearchQuery: Self {
        .internal(.clearPendingSearchQuery)
    }

    public static func setPresented(_ isPresented: Bool) -> Self {
        .view(.setPresented(isPresented))
    }

    public static func setText(_ text: String) -> Self {
        .view(.setText(text))
    }

    public static func scopeEditorOpen(
        editingPath: String?,
        favorites: [ScopeFavoriteItem],
        backHistory: [String],
    ) -> Self {
        .view(.scopeEditorOpen(editingPath: editingPath, favorites: favorites, backHistory: backHistory))
    }

    public static func scopeEditorSetPresented(_ isPresented: Bool) -> Self {
        .view(.scopeEditorSetPresented(isPresented))
    }

    public static func scopeEditorSetQueryText(_ text: String) -> Self {
        .view(.scopeEditorSetQueryText(text))
    }

    public static func scopeEditorSetIncludeSubfolders(_ includeSubfolders: Bool) -> Self {
        .view(.scopeEditorSetIncludeSubfolders(includeSubfolders))
    }

    public static func candidateScope(_ action: CandidateScope) -> Self {
        .view(.candidateScope(action))
    }

    public static func currentScope(_ action: CurrentScope) -> Self {
        .view(.currentScope(action))
    }

    public static func exceptionScope(_ action: ExceptionScope) -> Self {
        .view(.exceptionScope(action))
    }

    public static func addScope(path: String) -> Self {
        .view(.candidateScope(.add(path: path)))
    }

    public static func removeScope(path: String) -> Self {
        .view(.currentScope(.remove(path: path)))
    }

    public static func updateScope(oldPath: String, newPath: String) -> Self {
        .view(.currentScope(.replace(oldPath: oldPath, newPath: newPath)))
    }

    public static func excludeScope(path: String) -> Self {
        .view(.exceptionScope(.exclude(path: path)))
    }

    public static func restoreScope(path: String) -> Self {
        .view(.exceptionScope(.restore(path: path)))
    }

    public static func addCondition(propertyKey: String) -> Self {
        .view(.addCondition(propertyKey: propertyKey))
    }

    public static func searchResponse(
        _ requestID: UUID,
        _ result: Result<VoyagerShared.SearchResponsePayload, Error>,
    ) -> Self {
        .internal(.searchResponse(requestID, result))
    }

    public static func scopeEditorSeedCurrentPath(_ currentPath: String) -> Self {
        .internal(.scopeEditorSeedCurrentPath(currentPath))
    }

    public static func scopeEditorSearchResponse(
        _ query: String,
        _ result: Result<[ComposerScopeUtils.DirectoryItem], Error>,
    ) -> Self {
        .internal(.scopeEditorSearchResponse(query, result))
    }

    public static func filtersResponse(
        _ requestID: UUID,
        _ result: Result<VoyagerShared.SearchResponsePayload, Error>,
    ) -> Self {
        .internal(.filtersResponse(requestID, result))
    }

    public static func dismissTransientFeedback(id: UUID) -> Self {
        .internal(.dismissTransientFeedback(id))
    }

    public static func applyCollectionDraftRestore(_ payload: CollectionDraftRestorePayload) -> Self {
        .internal(.applyCollectionDraftRestore(payload))
    }

    public static func applyCollectionNavigationComposer(_ payload: CollectionNavigationStatePayload) -> Self {
        .internal(.applyCollectionNavigationComposer(payload))
    }

    public static func syncCollectionState(
        context: CollectionContext?,
        url: URL?,
        compatibility: CollectionFileCompatibilityMetadata?,
        isCollectionMode: Bool,
    ) -> Self {
        .internal(.syncCollectionState(
            context: context,
            url: url,
            compatibility: compatibility,
            isCollectionMode: isCollectionMode,
        ))
    }

    public static func updateLastFiltersResponse(_ response: VoyagerShared.SearchResponsePayload) -> Self {
        .internal(.updateLastFiltersResponse(response))
    }

    public static func setPendingSearchQuery(_ query: String?) -> Self {
        .internal(.setPendingSearchQuery(query))
    }

    public static func setLoadingFilters(_ isLoading: Bool) -> Self {
        .internal(.setLoadingFilters(isLoading))
    }

    public static func setInitialScope(_ path: String) -> Self {
        .internal(.setInitialScope(path))
    }

    public static func resetComposerAndSync(
        context: CollectionContext?,
        url: URL?,
        compatibility: CollectionFileCompatibilityMetadata?,
        isCollectionMode: Bool,
    ) -> Self {
        .internal(.resetComposerAndSync(
            context: context,
            url: url,
            compatibility: compatibility,
            isCollectionMode: isCollectionMode,
        ))
    }

    static func removeCondition(id: UUID) -> Self {
        .view(.removeCondition(id: id))
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

struct FilterSnapshot: Equatable {
    let scopes: [String]
    let conditions: [Condition]
    let conditionDisplayByKey: [String: ConditionDisplayState]
}

struct ConditionDisplayState: Equatable {
    var values: [String]
    var unitValueState: UnitValueState?
}

@ObservableState
struct ComposerState: Equatable {
    var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    var operatorPicker: OperatorPickerFeature.State = .init()
    var valuePicker: ValuePickerFeature.State = .init()

    var isPresented: Bool = false
    var collectionContext: CollectionContext?
    var openedCollectionURL: URL?
    var openedCollectionCompatibility: CollectionFileCompatibilityMetadata?
    var isCollectionMode: Bool = false
    var pendingSearchQuery: String?

    var text: String = ""
    var scopes: [String] = []
    var conditions: [Condition] = []
    var conditionDisplayByKey: [String: ConditionDisplayState] = [:]
    var operatorOptionsByKey: [String: [String]] = [:]
    var focusRequestID: Int = 0

    var history: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
    var redoHistory: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?

    var isLoadingSearch: Bool = false
    var isLoadingFilters: Bool = false
    var isFilteringInFlight: Bool = false
    var queryRenderPhase: ComposerQueryRenderPhase = .idle
    var transientFeedback: ComposerTransientFeedback?
    var submittedSearchFilters: VoyagerShared.SearchFiltersPayload?
    var activeSearchRequestID: UUID?
    var activeFiltersRequestID: UUID?
    var lastAcceptedSearchRequestID: UUID?
    var lastAcceptedFiltersRequestID: UUID?

    var lastSearchResponse: VoyagerShared.SearchResponsePayload?
    var lastFiltersResponse: VoyagerShared.SearchResponsePayload?
    var searchStartedAt: Date?
    var filtersStartedAt: Date?
    var hasSubmittedInSession: Bool = false

    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }
    var isCollectionSearching: Bool {
        let isSearching = isLoadingSearch
            || isLoadingFilters
            || queryRenderPhase == .chipsAppliedPendingList
        let hasContext = isCollectionMode
            || pendingSearchQuery != nil
            || !scopes.isEmpty
            || !conditions.isEmpty
        return isSearching && hasContext
    }

    mutating func pushHistory() {
        history.append(
            FilterSnapshot(
                scopes: scopes,
                conditions: conditions,
                conditionDisplayByKey: conditionDisplayByKey,
            ),
        )
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        redoHistory.removeAll()
    }

    mutating func clearHistory() {
        history.removeAll()
        redoHistory.removeAll()
    }

    mutating func applyCollectionDraftRestorePayload(_ payload: CollectionDraftRestorePayload) {
        let trimmedQuery = payload.context.query.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        if payload.openedURL == nil {
            text = payload.context.query
        } else {
            text = ""
        }
        scopes = payload.context.scopes
        conditions = payload.context.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    mutating func applyCollectionNavigationComposerPayload(_ payload: CollectionNavigationStatePayload) {
        let trimmedQuery = payload.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSearchQuery = trimmedQuery.isEmpty ? nil : trimmedQuery
        text = payload.composerText
        scopes = payload.scopes
        conditions = payload.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
    }

    mutating func applyCollectionOpenRestorationComposerPayload(
        _ payload: CollectionOpenRestorationPayload,
        registryClient: RegistryClient,
    ) {
        pendingSearchQuery = payload.context.query.isEmpty ? nil : payload.context.query
        text = payload.context.query
        scopes = payload.context.scopes
        conditions = payload.context.conditions
        propertyPicker = ConditionPropertyPickerFeature.State()
        operatorPicker = OperatorPickerFeature.State()
        valuePicker = ValuePickerFeature.State()
        clearHistory()
        let filters = buildFilters(from: self)
        applyAppliedFilters(
            .init(scopes: filters.scopes, conditions: filters.conditions),
            state: &self,
            registryClient: registryClient,
        )
        lastFiltersResponse = nil
        lastSearchResponse = nil
    }

    mutating func applyHydratedCollectionOpenComposerPayload(
        _ payload: CollectionHydratedOpenPayload,
        navigation: ContentPageCollectionNavigation,
    ) {
        lastFiltersResponse = payload.lastFiltersResponse
        lastSearchResponse = payload
            .lastSearchResponse ?? (navigation.context.query.isEmpty ? nil : payload.lastFiltersResponse)
    }
}

import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

public struct FilterSnapshot: Equatable {
    public let scopes: [String]
    public let conditions: [Condition]
    public let conditionDisplayByKey: [String: ConditionDisplayState]

    public init(scopes: [String], conditions: [Condition], conditionDisplayByKey: [String: ConditionDisplayState]) {
        self.scopes = scopes
        self.conditions = conditions
        self.conditionDisplayByKey = conditionDisplayByKey
    }
}

public struct ConditionDisplayState: Equatable {
    public var values: [String]
    public var unitValueState: UnitValueState?

    public init(values: [String], unitValueState: UnitValueState?) {
        self.values = values
        self.unitValueState = unitValueState
    }
}

@ObservableState
public struct ComposerState: Equatable {
    public var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    public var operatorPicker: OperatorPickerFeature.State = .init()
    public var valuePicker: ValuePickerFeature.State = .init()

    public var isPresented: Bool = false
    public var collectionContext: CollectionContext?
    public var openedCollectionURL: URL?
    public var openedCollectionCompatibility: CollectionFileCompatibilityMetadata?
    public var isCollectionMode: Bool = false
    public var pendingSearchQuery: String?

    public var text: String = ""
    public var scopes: [String] = []
    public var conditions: [Condition] = []
    public var conditionDisplayByKey: [String: ConditionDisplayState] = [:]
    public var operatorOptionsByKey: [String: [String]] = [:]
    public var focusRequestID: Int = 0

    public var history: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
    public var redoHistory: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?

    public var isLoadingSearch: Bool = false
    public var isLoadingFilters: Bool = false
    public var isFilteringInFlight: Bool = false
    public var queryRenderPhase: ComposerQueryRenderPhase = .idle
    public var transientFeedback: ComposerTransientFeedback?
    public var submittedSearchFilters: VoyagerShared.SearchFiltersPayload?
    public var activeSearchRequestID: UUID?
    public var activeFiltersRequestID: UUID?
    public var lastAcceptedSearchRequestID: UUID?
    public var lastAcceptedFiltersRequestID: UUID?

    public var lastSearchResponse: VoyagerShared.SearchResponsePayload?
    public var lastFiltersResponse: VoyagerShared.SearchResponsePayload?
    public var searchStartedAt: Date?
    public var filtersStartedAt: Date?
    public var hasSubmittedInSession: Bool = false

    public init() {}

    public var canUndo: Bool { !history.isEmpty }
    public var canRedo: Bool { !redoHistory.isEmpty }
    public var isCollectionSearching: Bool {
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
                conditionDisplayByKey: conditionDisplayByKey
            )
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

    public mutating func applyCollectionDraftRestorePayload(_ payload: CollectionDraftRestorePayload) {
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

    public mutating func applyCollectionNavigationComposerPayload(_ payload: CollectionNavigationStatePayload) {
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

    public mutating func applyCollectionOpenRestorationComposerPayload(
        _ payload: CollectionOpenRestorationPayload,
        registryClient: RegistryClient
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
            registryClient: registryClient
        )
        lastFiltersResponse = nil
        lastSearchResponse = nil
    }

    public mutating func applyHydratedCollectionOpenComposerPayload(
        _ payload: CollectionHydratedOpenPayload,
        navigation: ContentPageCollectionNavigation
    ) {
        lastFiltersResponse = payload.lastFiltersResponse
        lastSearchResponse = payload
            .lastSearchResponse ?? (navigation.context.query.isEmpty ? nil : payload.lastFiltersResponse)
    }
}

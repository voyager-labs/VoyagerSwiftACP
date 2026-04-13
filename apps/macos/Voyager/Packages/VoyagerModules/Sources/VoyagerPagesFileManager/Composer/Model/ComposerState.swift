import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerShared

public struct FilterSnapshot: Equatable {
    public let scopes: [String]
    public let conditions: [Condition]
    public let conditionDisplayByKey: [String: ConditionDisplayState]
}

public struct ConditionDisplayState: Equatable {
    public var values: [String]
    public var unitValueState: UnitValueState?
}

@ObservableState
public struct ComposerState: Equatable {
    public var collection: CollectionState = .init()
    public var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    public var operatorPicker: OperatorPickerFeature.State = .init()
    public var valuePicker: ValuePickerFeature.State = .init()

    public var isPresented: Bool = false
    public var collectionContext: CollectionContext?
    public var openedCollectionURL: URL?
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

    public mutating func pushHistory() {
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

    public mutating func clearHistory() {
        history.removeAll()
        redoHistory.removeAll()
    }
}

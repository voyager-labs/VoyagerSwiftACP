import ComposableArchitecture
import Foundation

struct FilterSnapshot: Equatable {
    let scopes: [String]
    let conditions: [Condition]
}

@ObservableState
struct ComposerState: Equatable {
    var collection: CollectionFeature.State = .init()
    var propertyPicker: ConditionPropertyPickerFeature.State = .init()
    var operatorPicker: OperatorPickerFeature.State = .init()
    var valuePicker: ValuePickerFeature.State = .init()

    var isPresented: Bool = false
    var collectionContext: CollectionContext?
    var openedCollectionURL: URL?
    var isCollectionMode: Bool = false
    var pendingSearchQuery: String?
    var text: String = ""
    var scopes: [String] = []
    var conditions: [Condition] = []
    var operatorOptionsByKey: [String: [String]] = [:]
    var focusRequestID: Int = 0
    var history: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
    var redoHistory: [FilterSnapshot] = [] // 이 히스토리는 UndoManager를 사용하도록 변경해야 하는 것이 아닌가?
    var isLoadingSearch: Bool = false
    var isLoadingFilters: Bool = false
    var isFilteringInFlight: Bool = false
    var lastSearchResponse: SearchResponsePayload?
    var lastFiltersResponse: SearchResponsePayload?
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

    var queryRenderPhase: ComposerQueryRenderPhase = .idle

    mutating func pushHistory() {
        history.append(FilterSnapshot(scopes: scopes, conditions: conditions))
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        redoHistory.removeAll()
    }

    mutating func clearHistory() {
        history.removeAll()
        redoHistory.removeAll()
    }
}

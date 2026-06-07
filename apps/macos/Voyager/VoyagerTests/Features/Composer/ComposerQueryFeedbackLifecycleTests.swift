import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerQueryFeedbackLifecycleTests: XCTestCase {
    func testChangedFiltersContinueToApplyFiltersWithoutShowingToast() async throws {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = changedFiltersSearchResponse()
        let initialState = searchLoadingState(activeRequestID: activeRequestID)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 2,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(searchResponse)))

        let filtersRequestID = try XCTUnwrap(store.state.activeFiltersRequestID)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .delayed)
        XCTAssertEqual(
            store.state.lastScopeChangeFeedback?.pendingResultRequest,
            .filters(filtersRequestID),
        )

        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
        XCTAssertEqual(store.state.lastAcceptedFiltersRequestID, filtersRequestID)
        XCTAssertEqual(store.state.lastFiltersResponse?.itemCount, 2)

        let recordedRequest = applyRecorder.last()
        XCTAssertEqual(recordedRequest?.filters.conditions.count, 1)
        XCTAssertNil(store.state.transientFeedback)
        XCTAssertFalse(store.state.isLoadingFilters)
    }

    func testNoOpSearchSkipsApplyFiltersWithoutShowingFeedback() async {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = noOpSearchResponse()
        let initialState = searchLoadingState(activeRequestID: activeRequestID)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 0,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(searchResponse)))

        XCTAssertNil(applyRecorder.last())
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.idle)
        XCTAssertNil(store.state.transientFeedback)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
    }


    func testNoOpSearchRefreshesFiltersWhenCollectionIsOpen() async throws {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        var initialState = searchLoadingState(activeRequestID: activeRequestID)
        initialState.openedCollectionURL = URL(fileURLWithPath: "/tmp/collection.voyagercollection")

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 2,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(noOpSearchResponse())))

        let filtersRequestID = try XCTUnwrap(store.state.activeFiltersRequestID)
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.chipsAppliedPendingList)
        XCTAssertTrue(store.state.isLoadingFilters)
        XCTAssertEqual(applyRecorder.last()?.filters.scopes, ["/tmp"])

        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(store.state.lastAcceptedFiltersRequestID, filtersRequestID)
        XCTAssertEqual(store.state.lastFiltersResponse?.itemCount, 2)
        XCTAssertFalse(store.state.isLoadingFilters)
    }

    func testFallbackReuseRefreshesFiltersWhenCollectionIsOpenAndShowsInfoFeedback() async throws {
        let applyRecorder = ApplyFiltersRecorder()
        let clock = TestClock()
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(
                scopes: ["/tmp"],
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            ),
            items: nil,
            error: nil,
            queryOutcome: .fallbackReuse,
        )
        var initialState = searchLoadingState(activeRequestID: activeRequestID)
        initialState.openedCollectionURL = URL(fileURLWithPath: "/tmp/collection.voyagercollection")

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.registryClient = makeRegistryClient()
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return VoyagerShared.SearchResponsePayload(
                    itemCount: 1,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(activeRequestID, .success(searchResponse)))

        XCTAssertEqual(store.state.transientFeedback?.kind, .info)
        XCTAssertEqual(store.state.transientFeedback?.message, ComposerQueryFeedbackPolicy.fallbackReuseMessage)
        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.chipsAppliedPendingList)
        XCTAssertTrue(store.state.isLoadingFilters)
        XCTAssertEqual(applyRecorder.last()?.filters.conditions.count, 1)

        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(store.state.lastFiltersResponse?.itemCount, 1)
        XCTAssertFalse(store.state.isLoadingFilters)
    }

    func testFallbackReuseSearchShowsInfoFeedbackWithoutApplyingFilters() {
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(
                scopes: ["/tmp"],
                excludedScopes: ["/tmp/excluded"],
                includeSubfolders: true,
                includeDirectories: true,
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            ),
            items: nil,
            error: nil,
            queryOutcome: .fallbackReuse,
        )

        var initialState = searchLoadingState(activeRequestID: activeRequestID)
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
        )

        var state = initialState
        _ = ComposerFeature().reduce(
            into: &state,
            action: ComposerAction.searchResponse(activeRequestID, .success(searchResponse)),
        )

        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertEqual(state.transientFeedback?.kind, .info)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.fallbackReuseMessage)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
    }

    func testLegacyOutcomeNilStillAppliesFilters() {
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(
                scopes: ["/tmp"],
                conditions: [
                    VoyagerShared.SearchConditionPayload(
                        propertyKey: "name",
                        operator: "contains",
                        value: .string("draft"),
                    ),
                ],
            ),
            items: nil,
            error: nil,
            queryOutcome: nil,
        )

        var initialState = searchLoadingState(activeRequestID: activeRequestID)
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])

        var state = initialState
        withDependencies {
            $0.registryClient = makeRegistryClient()
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: ComposerAction.searchResponse(activeRequestID, .success(searchResponse)),
            )
        }

        XCTAssertTrue(state.isLoadingFilters)
        XCTAssertTrue(state.isFilteringInFlight)
        XCTAssertEqual(state.queryRenderPhase, .chipsAppliedPendingList)
        XCTAssertNotNil(state.activeFiltersRequestID)
    }

    func testCancelSearchResolvesDelayedScopeFeedback() async {
        let activeRequestID = UUID()
        let initialState = searchLoadingState(activeRequestID: activeRequestID)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.cancelSearch)

        XCTAssertFalse(store.state.isLoadingSearch)
        XCTAssertNil(store.state.activeSearchRequestID)
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
    }

    func testCancelFiltersResolvesDelayedScopeFeedback() async {
        let activeRequestID = UUID()
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingFilters = true
        initialState.isFilteringInFlight = true
        initialState.queryRenderPhase = .chipsAppliedPendingList
        initialState.activeFiltersRequestID = activeRequestID
        initialState.pendingSearchQuery = "draft"
        initialState.lastScopeChangeFeedback = scopeChangeFeedback(
            phase: .delayed,
            pendingResultRequest: .filters(activeRequestID),
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.cancelFilters)

        XCTAssertFalse(store.state.isLoadingFilters)
        XCTAssertFalse(store.state.isFilteringInFlight)
        XCTAssertNil(store.state.activeFiltersRequestID)
        XCTAssertNil(store.state.pendingSearchQuery)
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
    }

    func testSearchFailureShowsPolicyErrorFeedback() async {
        let activeRequestID = UUID()
        let initialState = searchLoadingState(activeRequestID: activeRequestID)

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.searchResponse(
            activeRequestID,
            .failure(MockLocalizedError("LLM_CONVERSION_FAILED: timeout")),
        ))

        XCTAssertEqual(store.state.transientFeedback?.kind, .error)
        XCTAssertEqual(store.state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertEqual(store.state.queryRenderPhase, .failed)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .failed)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
    }

    func testApplyFiltersFailureDoesNotMutateScopeFeedbackAfterUnrelatedHistoryChange() async throws {
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.lastScopeChangeFeedback = scopeChangeFeedback(
            phase: .visible,
            pendingResultRequest: nil,
        )
        initialState.history = [
            FilterSnapshot(
                scopeSelection: initialState.scopeEditor.selection,
                conditions: initialState.conditions,
                conditionDisplayByKey: initialState.conditionDisplayByKey,
                includeSubfolders: initialState.scopeEditor.includeSubfolders,
            ),
        ]

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { _ in
                throw MockLocalizedError("HELPER_UNAVAILABLE: condition failure")
            }
        }
        store.exhaustivity = .off

        await store.send(.applyFilters)

        let filtersRequestID = try XCTUnwrap(store.state.activeFiltersRequestID)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)

        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .visible)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
        XCTAssertEqual(store.state.lastAcceptedFiltersRequestID, filtersRequestID)
        XCTAssertEqual(store.state.transientFeedback?.kind, .error)
        XCTAssertEqual(
            store.state.transientFeedback?.message,
            ComposerQueryFeedbackPolicy.executionFailureMessage,
        )
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
    }

    func testApplyFiltersFailureMarksScopeFeedbackFailed() async throws {
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.lastScopeChangeFeedback = scopeChangeFeedback(
            phase: .visible,
            pendingResultRequest: nil,
        )

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.searchClient.applyFilters = { _ in
                throw MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")
            }
        }
        store.exhaustivity = .off

        await store.send(.applyFilters)

        let filtersRequestID = try XCTUnwrap(store.state.activeFiltersRequestID)
        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .delayed)
        XCTAssertEqual(
            store.state.lastScopeChangeFeedback?.pendingResultRequest,
            .filters(filtersRequestID),
        )

        await store.receive(\.internal.filtersResponse)

        XCTAssertEqual(store.state.lastScopeChangeFeedback?.phase, .failed)
        XCTAssertNil(store.state.lastScopeChangeFeedback?.pendingResultRequest)
        XCTAssertEqual(store.state.lastAcceptedFiltersRequestID, filtersRequestID)
        XCTAssertEqual(store.state.transientFeedback?.kind, .error)
        XCTAssertEqual(
            store.state.transientFeedback?.message,
            ComposerQueryFeedbackPolicy.executionFailureMessage,
        )
        XCTAssertEqual(store.state.queryRenderPhase, .idle)
    }

    func testStaleFilterResponseDoesNotMutateFeedbackOrPhase() async {
        let activeRequestID = UUID()
        let staleRequestID = UUID()
        let initialFeedback = ComposerTransientFeedback(id: UUID(), kind: .info, message: "existing")
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingFilters = true
        initialState.isFilteringInFlight = true
        initialState.queryRenderPhase = .chipsAppliedPendingList
        initialState.transientFeedback = initialFeedback
        initialState.activeFiltersRequestID = activeRequestID

        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        }
        store.exhaustivity = .off

        await store.send(ComposerAction.filtersResponse(
            staleRequestID,
            .failure(MockLocalizedError("HELPER_UNAVAILABLE: xpc disconnected")),
        ))

        XCTAssertEqual(store.state.queryRenderPhase, ComposerQueryRenderPhase.chipsAppliedPendingList)
        XCTAssertEqual(store.state.transientFeedback, initialFeedback)
        XCTAssertEqual(store.state.activeFiltersRequestID, activeRequestID)
    }
}

@MainActor
private func searchLoadingState(activeRequestID: UUID) -> ComposerState {
    var state = ComposerState()
    state.scopes = ["/tmp"]
    state.isLoadingSearch = true
    state.queryRenderPhase = .searching
    state.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
    state.activeSearchRequestID = activeRequestID
    state.lastScopeChangeFeedback = scopeChangeFeedback(
        phase: .delayed,
        pendingResultRequest: .search(activeRequestID),
    )
    return state
}

@MainActor
private func scopeChangeFeedback(
    phase: ComposerScopeChangeFeedbackPhase,
    pendingResultRequest: ScopeFeedbackPendingRequest?,
) -> ComposerScopeChangeFeedback {
    ComposerScopeChangeFeedback(
        id: UUID(),
        beforeScope: ComposerScopeSnapshot(scopeSelection: .rootOnly, includeSubfolders: true),
        afterScope: ComposerScopeSnapshot(scopeSelection: explicitTmpScope(), includeSubfolders: true),
        origin: .addBase,
        phase: phase,
        pendingResultRequest: pendingResultRequest,
        historyDepthAfterCommit: 0,
        redoDepthAfterCommit: 0,
    )
}

@MainActor
private func explicitTmpScope() -> ComposerScopeSelection {
    .explicit(
        bases: [ComposerScopeBase(path: "/tmp")],
        exceptions: [],
    )
}

private func changedFiltersSearchResponse() -> VoyagerShared.SearchResponsePayload {
    VoyagerShared.SearchResponsePayload(
        itemCount: 0,
        appliedFilters: VoyagerShared.AppliedFiltersPayload(
            scopes: ["/tmp"],
            conditions: [
                VoyagerShared.SearchConditionPayload(
                    propertyKey: "name",
                    operator: "contains",
                    value: .string("draft"),
                ),
            ],
        ),
        items: nil,
        error: nil,
        queryOutcome: .convertedChanged,
    )
}

private func noOpSearchResponse() -> VoyagerShared.SearchResponsePayload {
    VoyagerShared.SearchResponsePayload(
        itemCount: 0,
        appliedFilters: VoyagerShared.AppliedFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
        ),
        items: nil,
        error: nil,
        queryOutcome: .unchangedResult,
    )
}

private final class ApplyFiltersRecorder: @unchecked Sendable {
    private var requests: [VoyagerShared.FiltersOnlyRequestPayload] = []

    func record(_ request: VoyagerShared.FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> VoyagerShared.FiltersOnlyRequestPayload? {
        requests.last
    }
}

private struct MockLocalizedError: LocalizedError, Equatable {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}

private extension VoyagerShared.SearchFiltersPayload {
    var asAppliedFiltersPayload: VoyagerShared.AppliedFiltersPayload {
        VoyagerShared.AppliedFiltersPayload(
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            includeDirectories: includeDirectories,
            conditions: conditions,
        )
    }
}

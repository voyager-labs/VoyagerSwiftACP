import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerQueryFeedbackLifecycleTests: XCTestCase {
    func testChangedFiltersContinueToApplyFiltersWithoutShowingToast() {
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
            queryOutcome: .convertedChanged,
        )

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

        var state = initialState
        withDependencies {
            $0.registryClient = makeRegistryClient()
        } operation: {
            _ = ComposerFeature().reduce(
                into: &state,
                action: ComposerAction.searchResponse(activeRequestID, .success(searchResponse)),
            )
        }

        XCTAssertNil(state.transientFeedback)
        XCTAssertTrue(state.isLoadingFilters)
        XCTAssertTrue(state.isFilteringInFlight)
        XCTAssertEqual(state.queryRenderPhase, .chipsAppliedPendingList)
        XCTAssertNotNil(state.activeFiltersRequestID)
    }

    func testNoOpSearchSkipsApplyFiltersWithoutShowingFeedback() {
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
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

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

        var state = initialState
        _ = ComposerFeature().reduce(
            into: &state,
            action: ComposerAction.searchResponse(activeRequestID, .success(searchResponse)),
        )

        XCTAssertEqual(state.queryRenderPhase, .idle)
        XCTAssertNil(state.transientFeedback)
        XCTAssertFalse(state.isLoadingFilters)
        XCTAssertFalse(state.isFilteringInFlight)
    }


    func testNoOpSearchRefreshesFiltersWhenCollectionIsOpen() async throws {
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        let searchResponse = VoyagerShared.SearchResponsePayload(
            itemCount: 0,
            appliedFilters: VoyagerShared.AppliedFiltersPayload(
                scopes: ["/tmp"],
                conditions: [],
            ),
            items: nil,
            error: nil,
            queryOutcome: .unchangedResult,
        )

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.openedCollectionURL = URL(fileURLWithPath: "/tmp/collection.voyagercollection")
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

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

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.openedCollectionURL = URL(fileURLWithPath: "/tmp/collection.voyagercollection")
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

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

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            includeDirectories: true,
            conditions: [],
        )
        initialState.activeSearchRequestID = activeRequestID

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

        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.submittedSearchFilters = VoyagerShared.SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
        initialState.activeSearchRequestID = activeRequestID

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

    func testSearchFailureShowsPolicyErrorFeedback() {
        let activeRequestID = UUID()
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        initialState.isLoadingSearch = true
        initialState.queryRenderPhase = .searching
        initialState.activeSearchRequestID = activeRequestID

        var state = initialState
        _ = ComposerFeature().reduce(into: &state, action: ComposerAction.searchResponse(
            activeRequestID,
            .failure(MockLocalizedError("LLM_CONVERSION_FAILED: timeout")),
        ))

        XCTAssertEqual(state.transientFeedback?.kind, .error)
        XCTAssertEqual(state.transientFeedback?.message, ComposerQueryFeedbackPolicy.conversionFailureMessage)
        XCTAssertEqual(state.queryRenderPhase, .failed)
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

private struct MockLocalizedError: LocalizedError, Equatable {
    let rawMessage: String

    init(_ rawMessage: String) {
        self.rawMessage = rawMessage
    }

    var errorDescription: String? {
        rawMessage
    }
}

private func makeRegistryClient() -> RegistryClient {
    .init(
        allProperties: { [] },
        labelForKey: { _ in "Name" },
        propertyTypeString: { _ in "string" },
        propertyUnitSpec: { _ in nil },
        operatorCodes: { _ in ["contains"] },
        operatorDefinition: { _ in
            .init(
                uiLabel: "Contains",
                mdqueryOperator: "CONTAINS",
                valueShape: ValueShape.single,
                valueCount: .fixed(1),
                allowedTypes: ["string"],
                inverseOf: nil,
                aliases: nil,
                uiValueKind: ["string": "singleText"],
            )
        },
        operatorValueUIKind: { _, _ in "singleText" },
        resolvePropertyKey: { .canonical($0) },
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

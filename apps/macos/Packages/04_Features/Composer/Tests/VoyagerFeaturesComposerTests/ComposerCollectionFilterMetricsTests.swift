import ComposableArchitecture
import Foundation
@testable import VoyagerFeaturesComposer
import VoyagerShared
import XCTest

@MainActor
final class ComposerCollectionFilterMetricsTests: XCTestCase {
    func testUnchangedResultWithoutOpenedCollectionLogsQueryMetricOnly() async {
        let recorder = ComposerMetricRecorder()
        let activeRequestID = UUID()
        let store = TestStore(initialState: searchLoadingState(activeRequestID: activeRequestID)) {
            ComposerFeature()
        } withDependencies: {
            $0.composerMetricClient = recorder.client
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(activeRequestID, .success(noOpSearchResponse())))

        let queryMetric = recorder.lastMetric(named: ComposerCollectionFilterMetrics.queryResult)
        XCTAssertEqual(queryMetric?.tags["outcome"], SearchQueryConversionOutcomePayload.unchangedResult.rawValue)
        XCTAssertEqual(queryMetric?.tags["opened_collection"], "false")
        XCTAssertNil(recorder.lastMetric(named: ComposerCollectionFilterMetrics.applyResult))
    }

    func testOpenedCollectionUnchangedResultLogsQueryAndApplyMetrics() async {
        let recorder = ComposerMetricRecorder()
        let applyRecorder = ApplyFiltersRecorder()
        let activeRequestID = UUID()
        var initialState = searchLoadingState(activeRequestID: activeRequestID)
        initialState.openedCollectionURL = URL(fileURLWithPath: "/tmp/collection.voyagercollection")
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.composerMetricClient = recorder.client
            $0.searchClient.applyFilters = { request in
                applyRecorder.record(request)
                return SearchResponsePayload(
                    itemCount: 3,
                    appliedFilters: request.filters.asAppliedFiltersPayload,
                    items: nil,
                    error: nil,
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(activeRequestID, .success(noOpSearchResponse())))
        await store.receive(\.internal.filtersResponse)

        let queryMetric = recorder.lastMetric(named: ComposerCollectionFilterMetrics.queryResult)
        XCTAssertEqual(queryMetric?.tags["outcome"], SearchQueryConversionOutcomePayload.unchangedResult.rawValue)
        XCTAssertEqual(queryMetric?.tags["opened_collection"], "true")
        let applyMetric = recorder.lastMetric(named: ComposerCollectionFilterMetrics.applyResult)
        XCTAssertEqual(applyMetric?.tags["outcome"], "applied")
        XCTAssertEqual(applyMetric?.tags["opened_collection"], "true")
        XCTAssertEqual(applyMetric?.tags["result_set"], "nonempty")
        XCTAssertEqual(applyMetric?.tags["source"], ComposerCollectionFilterMetrics.sourcePostQueryApply)
        XCTAssertNotNil(applyRecorder.last())
    }

    func testSearchFailureLogsConversionFailureMetricWithoutRawError() async {
        let recorder = ComposerMetricRecorder()
        let clock = TestClock()
        let activeRequestID = UUID()
        let store = TestStore(initialState: searchLoadingState(activeRequestID: activeRequestID)) {
            ComposerFeature()
        } withDependencies: {
            $0.composerMetricClient = recorder.client
            $0.continuousClock = clock
        }
        store.exhaustivity = .off

        await store.send(.searchResponse(
            activeRequestID,
            .failure(MockLocalizedError("LLM_CONVERSION_FAILED: secret path")),
        ))

        let metric = recorder.lastMetric(named: ComposerCollectionFilterMetrics.queryResult)
        XCTAssertEqual(metric?.tags["outcome"], "conversion_failure")
        XCTAssertEqual(metric?.tags["reason"], "conversion_error")
        XCTAssertFalse(metric?.tags.values.contains { $0.contains("secret") } ?? true)
    }

    func testApplyFailureLogsExecutionFailureMetric() async {
        let recorder = ComposerMetricRecorder()
        let clock = TestClock()
        var initialState = ComposerState()
        initialState.scopes = ["/tmp"]
        let store = TestStore(initialState: initialState) {
            ComposerFeature()
        } withDependencies: {
            $0.composerMetricClient = recorder.client
            $0.continuousClock = clock
            $0.searchClient.applyFilters = { _ in
                throw MockLocalizedError("HELPER_UNAVAILABLE: private details")
            }
        }
        store.exhaustivity = .off

        await store.send(.applyFilters)
        await store.receive(\.internal.filtersResponse)

        let metric = recorder.lastMetric(named: ComposerCollectionFilterMetrics.applyResult)
        XCTAssertEqual(metric?.tags["outcome"], "execution_failure")
        XCTAssertEqual(metric?.tags["reason"], "execution_error")
        XCTAssertEqual(metric?.tags["source"], ComposerCollectionFilterMetrics.sourceManualApply)
        XCTAssertFalse(metric?.tags.values.contains { $0.contains("private") } ?? true)
    }
}

private struct RecordedComposerMetric: Equatable {
    let name: String
    let value: Double
    let tags: [String: String]
    let level: ComposerMetricLevel
}

private final class ComposerMetricRecorder: @unchecked Sendable {
    private var metrics: [RecordedComposerMetric] = []

    var client: ComposerMetricClient {
        ComposerMetricClient { [weak self] name, value, tags, level in
            self?.metrics.append(.init(name: name, value: value, tags: tags ?? [:], level: level))
        }
    }

    func lastMetric(named name: String) -> RecordedComposerMetric? {
        metrics.last { $0.name == name }
    }
}

@MainActor
private func searchLoadingState(activeRequestID: UUID) -> ComposerState {
    var state = ComposerState()
    state.scopes = ["/tmp"]
    state.isLoadingSearch = true
    state.queryRenderPhase = .searching
    state.submittedSearchFilters = SearchFiltersPayload(scopes: ["/tmp"], conditions: [])
    state.activeSearchRequestID = activeRequestID
    return state
}

private func noOpSearchResponse() -> SearchResponsePayload {
    SearchResponsePayload(
        itemCount: 0,
        appliedFilters: AppliedFiltersPayload(
            scopes: ["/tmp"],
            excludedScopes: ["/tmp/excluded"],
            includeSubfolders: true,
            conditions: [],
        ),
        items: nil,
        error: nil,
        queryConversion: SearchQueryConversionMetadataPayload(outcome: .unchangedResult),
    )
}

private final class ApplyFiltersRecorder: @unchecked Sendable {
    private var requests: [FiltersOnlyRequestPayload] = []

    func record(_ request: FiltersOnlyRequestPayload) {
        requests.append(request)
    }

    func last() -> FiltersOnlyRequestPayload? {
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

private extension SearchFiltersPayload {
    var asAppliedFiltersPayload: AppliedFiltersPayload {
        AppliedFiltersPayload(
            scopes: scopes,
            excludedScopes: excludedScopes,
            includeSubfolders: includeSubfolders,
            conditions: conditions,
        )
    }
}

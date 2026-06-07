import ComposableArchitecture
import Foundation
@testable import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionFilterSaveMetricsTests: XCTestCase {
    func testSaveRequestedEmptyContentLogsBlockedMetricWithoutSensitiveContext() {
        let recorder = CollectionMetricRecorder()
        var state = CollectionState()
        let payload = SaveRequestPayload(
            context: nil,
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "fingerprint",
            capturedAt: Date(timeIntervalSince1970: 0),
            relevanceRoots: [],
            openedCompatibility: nil,
        )

        withDependencies {
            $0.collectionMetricClient = recorder.client
        } operation: {
            _ = CollectionFeature().reduce(into: &state, action: .saveRequested(payload))
        }

        let metric = recorder.lastMetric(named: CollectionFilterSaveMetrics.saveResult)
        XCTAssertEqual(metric?.tags["outcome"], "save_blocked")
        XCTAssertEqual(metric?.tags["reason"], "empty_content")
        XCTAssertEqual(metric?.tags["source"], "save_new")
        XCTAssertFalse(metric?.tags.values.contains { $0.contains("Complete") } ?? true)
    }

    func testSaveRequestedWhileSearchInFlightLogsBlockedMetric() {
        let recorder = CollectionMetricRecorder()
        var state = CollectionState()
        let payload = makePayload(isSearchLoading: true)

        withDependencies {
            $0.collectionMetricClient = recorder.client
        } operation: {
            _ = CollectionFeature().reduce(into: &state, action: .saveRequested(payload))
        }

        let metric = recorder.lastMetric(named: CollectionFilterSaveMetrics.saveResult)
        XCTAssertEqual(metric?.tags["outcome"], "save_blocked")
        XCTAssertEqual(metric?.tags["reason"], "search_inflight")
        XCTAssertEqual(metric?.level, .warn)
    }

    func testSavePanelCancelLogsCancelledMetric() {
        let recorder = CollectionMetricRecorder()
        var state = CollectionState()
        state.pendingSave = makeSnapshot()
        state.isSaving = true

        withDependencies {
            $0.collectionMetricClient = recorder.client
        } operation: {
            _ = CollectionFeature().reduce(into: &state, action: .savePanelResponse(nil))
        }

        let metric = recorder.lastMetric(named: CollectionFilterSaveMetrics.saveResult)
        XCTAssertEqual(metric?.tags["outcome"], "cancelled")
        XCTAssertEqual(metric?.tags["reason"], "none")
        XCTAssertEqual(metric?.tags["source"], "save_new")
        XCTAssertFalse(state.isSaving)
        XCTAssertNil(state.pendingSave)
    }

    func testSaveToExistingFailureLogsSaveFailedMetric() async {
        let recorder = CollectionMetricRecorder()
        let payload = makePayload()
        let url = URL(fileURLWithPath: "/tmp/test.voycoll")
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionMetricClient = recorder.client
            $0.collectionFileClient.save = { _, _ in
                throw NSError(domain: "CollectionFilterSaveMetricsTests", code: 1)
            }
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted)

        let metric = recorder.lastMetric(named: CollectionFilterSaveMetrics.saveResult)
        XCTAssertEqual(metric?.tags["outcome"], "save_failed")
        XCTAssertEqual(metric?.tags["reason"], "storage_error")
        XCTAssertEqual(metric?.tags["source"], "save_existing")
        XCTAssertEqual(metric?.tags["opened_collection"], "true")
        XCTAssertEqual(metric?.level, .error)
    }

    func testSaveToExistingSuccessLogsSavedMetric() async {
        let recorder = CollectionMetricRecorder()
        let payload = makePayload()
        let url = URL(fileURLWithPath: "/tmp/test.voycoll")
        let store = TestStore(initialState: CollectionState()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionMetricClient = recorder.client
            $0.collectionFileClient.save = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted)

        let metric = recorder.lastMetric(named: CollectionFilterSaveMetrics.saveResult)
        XCTAssertEqual(metric?.tags["outcome"], "saved")
        XCTAssertEqual(metric?.tags["reason"], "none")
        XCTAssertEqual(metric?.tags["source"], "save_existing")
        XCTAssertEqual(metric?.tags["opened_collection"], "true")
        XCTAssertEqual(metric?.tags["condition_count_bucket"], "0")
    }
}

private struct RecordedCollectionMetric: Equatable {
    let name: String
    let value: Double
    let tags: [String: String]
    let level: CollectionMetricLevel
}

private final class CollectionMetricRecorder: @unchecked Sendable {
    private var metrics: [RecordedCollectionMetric] = []

    var client: CollectionMetricClient {
        CollectionMetricClient { [weak self] name, value, tags, level in
            self?.metrics.append(.init(name: name, value: value, tags: tags, level: level))
        }
    }

    func lastMetric(named name: String) -> RecordedCollectionMetric? {
        metrics.last { $0.name == name }
    }
}

private func makePayload(
    isSearchLoading: Bool = false,
    isFiltersLoading: Bool = false,
) -> SaveRequestPayload {
    SaveRequestPayload(
        context: CollectionContext(query: "draft", scopes: ["/tmp"], conditions: []),
        isSearchLoading: isSearchLoading,
        isFiltersLoading: isFiltersLoading,
        snapshotItems: nil,
        definitionFingerprint: "fingerprint",
        capturedAt: Date(timeIntervalSince1970: 0),
        relevanceRoots: ["/tmp"],
        openedCompatibility: nil,
    )
}

private func makeSnapshot() -> CollectionSaveSnapshot {
    CollectionSaveSnapshot(
        query: "draft",
        scopes: ["/tmp"],
        excludedScopes: [],
        includeSubfolders: true,
        includeDirectories: false,
        conditions: [],
        snapshotItems: nil,
        definitionFingerprint: "fingerprint",
        capturedAt: Date(timeIntervalSince1970: 0),
        relevanceRoots: ["/tmp"],
    )
}

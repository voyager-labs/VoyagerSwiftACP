import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotSavePipelineTests: XCTestCase {
    func testSaveToExistingPersistsSnapshotAndClearsInvalidationState() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/collection.voycoll")
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "old-fingerprint",
                relevanceRoots: ["/tmp"],
                lastInvalidatedAt: .distantPast,
            ),
        )

        let payload = SaveRequestPayload(
            context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: []),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: [.string("/tmp/report.txt")],
            definitionFingerprint: "fingerprint",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in kEmptyCollectionFile },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertEqual(saved?.file.snapshot?.items, [.string("/tmp/report.txt")])
        XCTAssertEqual(saved?.file.snapshotMeta?.definitionFingerprint, "fingerprint")
        XCTAssertEqual(saved?.file.snapshotMeta?.relevanceRoots, ["/tmp"])
        XCTAssertEqual(saved?.file.snapshotMeta?.itemCount, 1)
        XCTAssertNil(stalenessClient.record(url.path)?.lastInvalidatedAt)
        XCTAssertNil(stalenessClient.record(url.path))
    }

    func testDefinitionOnlySaveLeavesSnapshotNil() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/collection.voycoll")

        let payload = SaveRequestPayload(
            context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: []),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "fingerprint",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in kEmptyCollectionFile },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved?.file.snapshot)
        XCTAssertEqual(saved?.file.snapshotMeta?.definitionFingerprint, "fingerprint")
        XCTAssertEqual(saved?.file.snapshotMeta?.itemCount, 0)
        XCTAssertNil(stalenessClient.record(url.path))
    }

    func testEmptySnapshotSavePersistsEmptySnapshotArray() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/empty.voycoll")

        let payload = SaveRequestPayload(
            context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: []),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: [],
            definitionFingerprint: "fingerprint",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in kEmptyCollectionFile },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertEqual(saved?.file.snapshot?.items, [])
        XCTAssertEqual(saved?.file.snapshotMeta?.itemCount, 0)
    }
}

private let kEmptyCollectionFile = VoyagerCollectionFile(
    id: "",
    name: "",
    createdAt: .distantPast,
    updatedAt: .distantPast,
    query: "",
    scopes: [],
    conditions: [],
    snapshot: nil,
    snapshotMeta: nil,
    appVersion: nil,
)

private actor SavedCollectionsRecorder {
    struct Entry {
        let file: VoyagerCollectionFile
        let url: URL
    }

    private var entries: [Entry] = []

    func append(file: VoyagerCollectionFile, url: URL) {
        entries.append(.init(file: file, url: url))
    }

    func last() -> Entry? {
        entries.last
    }
}

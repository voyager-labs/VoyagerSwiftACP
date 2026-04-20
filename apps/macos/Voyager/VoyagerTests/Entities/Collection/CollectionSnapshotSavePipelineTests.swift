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
                load: { _ in makeCollectionLoadResult(kEmptyCollectionFile, sourceSchemaVersion: 2) },
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
        assertSnapshotMeta(saved?.file, itemCount: 1)
        XCTAssertEqual(saved?.file.snapshot?.items, [.string("/tmp/report.txt")])
        assertRecordUpdated(stalenessClient: stalenessClient, url: url)
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
                load: { _ in makeCollectionLoadResult(kEmptyCollectionFile, sourceSchemaVersion: 2) },
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
        assertSnapshotMeta(saved?.file, itemCount: 0)
        assertRecordUpdated(stalenessClient: stalenessClient, url: url)
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
                load: { _ in makeCollectionLoadResult(kEmptyCollectionFile, sourceSchemaVersion: 2) },
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
        assertSnapshotMeta(saved?.file, itemCount: 0)
        assertRecordUpdated(stalenessClient: stalenessClient, url: url)
    }

    private func assertSnapshotMeta(_ file: VoyagerCollectionFile?, itemCount: Int) {
        XCTAssertEqual(file?.snapshotMeta?.definitionFingerprint, "fingerprint")
        XCTAssertEqual(file?.snapshotMeta?.relevanceRoots, ["/tmp"])
        XCTAssertEqual(file?.snapshotMeta?.itemCount, itemCount)
    }

    private func assertRecordUpdated(
        stalenessClient: CollectionStalenessClient,
        url: URL,
    ) {
        XCTAssertEqual(
            stalenessClient.record(url.path),
            .init(
                definitionFingerprint: "fingerprint",
                relevanceRoots: ["/tmp"],
                lastInvalidatedAt: nil,
            ),
        )
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

private func makeCollectionLoadResult(
    _ file: VoyagerCollectionFile,
    sourceSchemaVersion: Int?,
) -> CollectionFileLoadResult {
    .init(
        file: file,
        containerFormat: .package,
        compatibility: .init(
            sourceSchemaVersion: sourceSchemaVersion,
            migrationPath: sourceSchemaVersion == CollectionFileSchemaVersion.current
                ? [.currentSchemaV2]
                : [.definitionOnlyV1, .currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: sourceSchemaVersion == CollectionFileSchemaVersion.current,
            writeBackReason: sourceSchemaVersion == CollectionFileSchemaVersion.current
                ? .allowed
                : .blockedLegacyVersionUpgrade,
        ),
    )
}

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

import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class CollectionSnapshotSavePipelineTests: XCTestCase {
    // swiftlint:disable:next function_body_length
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
            openedCompatibility: nil,
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
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
            openedCompatibility: nil,
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
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
        XCTAssertNil(saved?.file.snapshotMeta)
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
            openedCompatibility: nil,
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
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

    func testSavePipelinePersistsCanonicalCurrentSchemaVersionForConstructedPayload() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/current-save.voycoll")

        let payload = SaveRequestPayload(
            context: CollectionContext(query: "Current", scopes: ["/tmp"], conditions: []),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "fingerprint",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
            openedCompatibility: nil,
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
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
        XCTAssertEqual(saved?.file.schemaVersion, CollectionFileSchemaVersion.definitionOnlyCurrent)
        XCTAssertNil(saved?.file.snapshotMeta)
    }

    func testSaveToExistingIsBlockedForFutureMinorCompatibility() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/future-minor.voycoll")

        let payload = SaveRequestPayload(
            context: CollectionContext(query: "Blocked", scopes: ["/tmp"], conditions: []),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: nil,
            definitionFingerprint: "fingerprint",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
            openedCompatibility: .init(
                sourceSchemaVersion: .init(major: 1, minor: 2),
                migrationPath: [.currentSchemaV2],
                warnings: [.futureMinorVersionReadOnly],
                usedDefinitionFallback: false,
                writeBackAllowed: false,
                writeBackReason: .blockedFutureMinorVersion,
            ),
        )

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { file, url in
                    await recorder.append(file: file, url: url)
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveToExisting(payload, url))
        await store.finish()

        let lastSaved = await recorder.last()
        XCTAssertNil(lastSaved)
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
    sourceSchemaVersion: SchemaVersion?,
) -> CollectionFileLoadResult {
    VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
        file: file,
        containerFormat: .package,
        sourceSchemaVersion: sourceSchemaVersion,
        warning: nil,
        usedDefinitionFallback: false,
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

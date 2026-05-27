// swiftlint:disable single_test_class
import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

/// 컬렉션 스냅샷 저장 파이프라인 — 정상/취소/실패 경로를 검증.
@MainActor
final class CollectionSnapshotSavePipelineTests: XCTestCase {
    /// testSaveToExistingPersistsSnapshotAndClearsInvalidationState 테스트 동작을 검증한다.
    func testSaveToExistingPersistsSnapshotAndClearsInvalidationState() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/collection.voycoll")
        seedStalenessRecord(stalenessClient: stalenessClient, url: url)

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

    /// testDefinitionOnlySaveLeavesSnapshotNil 테스트 동작을 검증한다.
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

    /// testEmptySnapshotSavePersistsEmptySnapshotArray 테스트 동작을 검증한다.
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

    /// testSavePipelinePersistsCanonicalCurrentSchemaVersionForConstructedPayload 테스트 동작을 검증한다.
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

    /// testSaveToExistingIsBlockedForFutureMinorCompatibility 테스트 동작을 검증한다.
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

private func seedStalenessRecord(stalenessClient: CollectionStalenessClient, url: URL) {
    stalenessClient.upsertRecord(
        url.path,
        .init(
            definitionFingerprint: "old-fingerprint",
            relevanceRoots: ["/tmp"],
            lastInvalidatedAt: .distantPast,
        ),
    )
}

let kEmptyCollectionFile = VoyagerCollectionFile(
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

func makeCollectionLoadResult(
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

actor SavedCollectionsRecorder {
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

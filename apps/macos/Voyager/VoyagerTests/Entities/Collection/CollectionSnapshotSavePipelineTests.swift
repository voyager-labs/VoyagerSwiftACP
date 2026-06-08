import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
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

    func testSaveToExistingPreservesExcludedScopesInFileAndStalenessRecord() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let url = URL(fileURLWithPath: "/tmp/excluded-save.voycoll")

        let payload = SaveRequestPayload(
            context: CollectionContext(
                query: "Report",
                scopes: ["/tmp"],
                excludedScopes: ["/tmp/ignored"],
                includeSubfolders: true,
                conditions: [],
            ),
            isSearchLoading: false,
            isFiltersLoading: false,
            snapshotItems: [.string("/tmp/report.txt")],
            definitionFingerprint: "fingerprint-with-excluded",
            capturedAt: .distantFuture,
            relevanceRoots: ["/tmp"],
            openedCompatibility: nil,
        )

        let store = makeSavePipelineStore(recorder: recorder, stalenessClient: stalenessClient)

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertEqual(saved?.file.excludedScopes, ["/tmp/ignored"])
        XCTAssertEqual(saved?.file.snapshotMeta?.definitionFingerprint, "fingerprint-with-excluded")
        XCTAssertEqual(
            stalenessClient.record(url.path),
            .init(
                definitionFingerprint: "fingerprint-with-excluded",
                relevanceRoots: ["/tmp"],
                excludedScopes: ["/tmp/ignored"],
                includeSubfolders: true,
                lastInvalidatedAt: nil,
            ),
        )
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

        let store = makeSavePipelineStore(recorder: recorder, stalenessClient: stalenessClient)

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

        let store = makeSavePipelineStore(recorder: recorder, stalenessClient: stalenessClient)

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.receive { action in
            guard case let .delegate(.saveFeedback(feedback)) = action else { return false }
            XCTAssertEqual(feedback.stage, .saveFailed)
            XCTAssertEqual(feedback.category, .saveFailed)
            XCTAssertEqual(feedback.title, "Unable to Save Collection")
            XCTAssertEqual(feedback.message, "Disk write failed")
            XCTAssertTrue(feedback.isRetryable)
            return true
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

        let store = makeSavePipelineStore(recorder: recorder, stalenessClient: stalenessClient)

        await store.send(.saveToExisting(payload, url)) {
            $0.isSaving = true
        }
        await store.receive(\.saveCompleted) {
            $0.isSaving = false
            $0.pendingSave = nil
        }
        await store.receive { action in
            guard case let .delegate(.saveFeedback(feedback)) = action else { return false }
            XCTAssertEqual(feedback.stage, .saveFailed)
            XCTAssertEqual(feedback.category, .saveFailed)
            XCTAssertEqual(feedback.title, "Unable to Save Collection")
            XCTAssertEqual(feedback.message, "Disk write failed")
            XCTAssertTrue(feedback.isRetryable)
            return true
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

        let store = makeSavePipelineStore(recorder: recorder, stalenessClient: stalenessClient)

        await store.send(.saveToExisting(payload, url))
        await store.receive { action in
            guard case let .delegate(.saveFeedback(feedback)) = action else { return false }
            XCTAssertEqual(feedback.stage, .saveBlocked)
            XCTAssertEqual(feedback.category, .futureMinorReadOnly)
            XCTAssertEqual(feedback.title, "Unable to Save Collection")
            XCTAssertFalse(feedback.isRetryable)
            return true
        }
        await store.finish()

        let lastSaved = await recorder.last()
        XCTAssertNil(lastSaved)
    }

    private func makeSavePipelineStore(
        recorder: SavedCollectionsRecorder,
        stalenessClient: CollectionStalenessClient,
    ) -> TestStore<CollectionFeature.State, CollectionFeature.Action> {
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
        return store
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
                excludedScopes: [],
                includeSubfolders: true,
                lastInvalidatedAt: nil,
            ),
        )
    }
}

@MainActor
final class CollectionSavePanelClientTests: XCTestCase {
    func testSaveRequestedHappyPathProceedsThroughPanelToSaveCompleted() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let selectedURL = URL(fileURLWithPath: "/tmp/test-happy.voycoll")

        let payload = makeValidSaveRequestPayload()

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
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in selectedURL },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted)
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.url.pathExtension, "voycoll")
        XCTAssertEqual(saved?.file.snapshot?.items, [.string("/tmp/report.txt")])
    }

    func testSaveRequestedCancelPathClearsPendingSaveWithoutWriting() async {
        let recorder = SavedCollectionsRecorder()
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)

        let payload = makeValidSaveRequestPayload()

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
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in nil },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved, "No file should be saved when panel is cancelled")
    }

    func testSaveRequestedFailurePathEmitsSaveCompletedFailure() async {
        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        let selectedURL = URL(fileURLWithPath: "/tmp/test-fail.voycoll")

        let payload = makeValidSaveRequestPayload()

        let store = TestStore(initialState: CollectionFeature.State()) {
            CollectionFeature()
        } withDependencies: {
            $0.collectionFileClient = CollectionFileClient(
                save: { _, _ in
                    throw NSError(domain: "test", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Disk write failed",
                    ])
                },
                load: { _ in
                    makeCollectionLoadResult(
                        kEmptyCollectionFile,
                        sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                    )
                },
            )
            $0.collectionSavePanelClient = CollectionSavePanelClient(
                presentSavePanel: { _ in selectedURL },
                defaultSaveDirectory: { _ in URL(fileURLWithPath: "/tmp") },
            )
            $0.userDefaultsClient = .testValue
            $0.collectionStalenessClient = stalenessClient
        }
        store.exhaustivity = .off

        await store.send(.saveRequested(payload))
        await store.receive(\.savePanelResponse)
        await store.receive(\.saveCompleted)
        await store.finish()
    }
}

private func makeValidSaveRequestPayload() -> SaveRequestPayload {
    SaveRequestPayload(
        context: CollectionContext(query: "Report", scopes: ["/tmp"], conditions: []),
        isSearchLoading: false,
        isFiltersLoading: false,
        snapshotItems: [.string("/tmp/report.txt")],
        definitionFingerprint: "fingerprint",
        capturedAt: .distantFuture,
        relevanceRoots: ["/tmp"],
        openedCompatibility: nil,
    )
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

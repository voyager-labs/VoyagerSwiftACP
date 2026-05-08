import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesCollection
import VoyagerShared
import XCTest

@MainActor
final class FileManagerCollectionRefreshPolicyTests: XCTestCase {
    func testRefreshSuccessStartsWriteBackWhenCollectionIsClean() async {
        let recorder = SavedCollectionsRecorder()
        let requestID = UUID()
        let url = URL(fileURLWithPath: "/tmp/refresh-success.voycoll")
        let response = makeFiltersResponse(paths: ["/tmp/report.txt"])

        let store = makeContentStore(
            initialState: makeRefreshingState(
                requestID: requestID,
                openedURL: url,
                query: "report",
                scopes: ["/tmp"],
                collectionContext: .init(query: "report", scopes: ["/tmp"], conditions: []),
            ),
            recorder: recorder,
        )
        store.exhaustivity = .off

        await store.send(.composer(.internal(.filtersResponse(requestID, .success(response))))) {
            $0.composer.lastFiltersResponse = response
            $0.composer.isLoadingFilters = false
            $0.collection.collectionSession.phase = .opened(
                kind: .hydratedSnapshot,
                base: .stale,
                inflight: .writingBackRefreshedSnapshot,
            )
        }
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .writeBackInFlight)
    }

    func testRefreshFailureKeepsStaleAndClearsRefreshFlag() async {
        struct RefreshError: Error {}

        let requestID = UUID()
        let store = makeContentStore(
            initialState: makeRefreshingState(
                requestID: requestID,
                openedURL: URL(fileURLWithPath: "/tmp/failure.voycoll"),
                query: "report",
                scopes: ["/tmp"],
                collectionContext: .init(query: "report", scopes: ["/tmp"], conditions: []),
            ),
            recorder: SavedCollectionsRecorder(),
        )
        store.exhaustivity = .off

        await store.send(.composer(.internal(.filtersResponse(requestID, .failure(RefreshError()))))) {
            $0.collection.collectionSession.phase = .refreshFailed(kind: .hydratedSnapshot)
        }
        await store.finish()

        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .writingBackRefreshedSnapshot)
        XCTAssertTrue(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
        XCTAssertEqual(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ), .missingBaseline)
    }

    func testRefreshSuccessSkipsWriteBackWhenCollectionIsDirty() async {
        let requestID = UUID()
        let response = makeFiltersResponse(paths: ["/tmp/report.txt"])
        let recorder = SavedCollectionsRecorder()
        let store = makeContentStore(
            initialState: makeRefreshingState(
                requestID: requestID,
                openedURL: URL(fileURLWithPath: "/tmp/dirty.voycoll"),
                query: "report",
                scopes: ["/tmp"],
                collectionContext: .init(query: "updated", scopes: ["/tmp"], conditions: []),
                baselineContext: .init(query: "report", scopes: ["/tmp"], conditions: []),
            ),
            recorder: recorder,
        )
        store.exhaustivity = .off

        await store.send(.composer(.internal(.filtersResponse(requestID, .success(response))))) {
            $0.composer.lastFiltersResponse = response
            $0.composer.isLoadingFilters = false
            $0.collection.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .refreshingHydratedSnapshot)
        XCTAssertNotEqual(store.state.collection.collectionSession.phase.inflightStatus, .writingBackRefreshedSnapshot)
        XCTAssertTrue(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
        XCTAssertNil(store.state.collection.refreshBlockingReason(
            isCollectionMode: store.state.isCollectionMode,
            isDirty: store.state.isOpenedCollectionDirty,
            isSearching: store.state.composer.isCollectionSearching,
        ))
    }

    func testRefreshSuccessSkipsWriteBackWhenCompatibilityBlocksWriteBack() async {
        let requestID = UUID()
        let response = makeFiltersResponse(paths: ["/tmp/report.txt"])
        let recorder = SavedCollectionsRecorder()
        let store = makeContentStore(
            initialState: makeRefreshingState(
                requestID: requestID,
                openedURL: URL(fileURLWithPath: "/tmp/fallback.voycoll"),
                query: "report",
                scopes: ["/tmp"],
                collectionContext: .init(query: "report", scopes: ["/tmp"], conditions: []),
                compatibility: .init(
                    sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
                    migrationPath: [.currentSchemaV2, .definitionFallbackFromMalformedSnapshot],
                    warnings: [.droppedMalformedSnapshot],
                    usedDefinitionFallback: true,
                    writeBackAllowed: false,
                    writeBackReason: .blockedDefinitionFallback,
                ),
            ),
            recorder: recorder,
        )
        store.exhaustivity = .off

        await store.send(.composer(.internal(.filtersResponse(requestID, .success(response))))) {
            $0.composer.lastFiltersResponse = response
            $0.composer.isLoadingFilters = false
            $0.collection.collectionSession.phase = .opened(kind: .hydratedSnapshot, base: .stale, inflight: .none)
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved)
        XCTAssertTrue(store.state.collection.collectionSession.phase.isStale)
        XCTAssertNil(store.state.collection.collectionSession.metadata.lastRefreshAt)
    }

    func testCompleteWriteBackUpdatesCompatibilityForDefinitionOnlyCollection() {
        let url = URL(fileURLWithPath: "/tmp/definition-only.voycoll")
        let completion = CollectionSaveCompletion(
            url: url,
            file: VoyagerCollectionFile(
                schemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                id: "definition-only",
                name: "Definition Only",
                createdAt: .distantPast,
                updatedAt: .distantFuture,
                query: "report",
                scopes: ["/tmp"],
                conditions: [],
                snapshot: nil,
                snapshotMeta: nil,
                appVersion: nil,
            ),
        )

        var state = FileManagerContentState()
        state.collection.collectionContext = .init(query: "report", scopes: ["/tmp"], conditions: [])

        _ = state.collection.completeWriteBack(completion)

        XCTAssertEqual(state.collection.collectionSession.document?.compatibility?.warnings, [])
        XCTAssertFalse(state.collection.collectionSession.document?.compatibility?.usedDefinitionFallback ?? true)
        XCTAssertTrue(state.collection.collectionSession.document?.compatibility?.writeBackAllowed ?? false)
        XCTAssertEqual(state.collection.collectionSession.document?.compatibility?.writeBackReason, .allowed)
    }
}

@MainActor
private func makeContentStore(
    initialState: FileManagerContentState,
    recorder: SavedCollectionsRecorder,
) -> TestStore<FileManagerContentState, FileManagerContentAction> {
    TestStore(initialState: initialState) {
        FileManagerContentFeature()
    } withDependencies: {
        $0.collectionAlertClient = .init(
            showUnsavedNavigationAlert: { .save },
            showCollectionOpenErrorAlert: { _, _ in },
        )
        $0.registryClient = .testValue
        $0.searchClient = .testValue
        $0.collectionFileClient = .init(
            save: { file, url in
                await recorder.append(file: file, url: url)
            },
            load: { _ in
                makeCollectionLoadResult(
                    VoyagerCollectionFile(
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
                    ),
                    sourceSchemaVersion: CollectionFileSchemaVersion.definitionOnlyCurrent,
                )
            },
        )
        $0.userDefaultsClient = .testValue
        $0.collectionStalenessClient = .testValue
        $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
    }
}

@MainActor
private func makeRefreshingState(
    requestID: UUID,
    openedURL: URL,
    query: String,
    scopes: [String],
    collectionContext: CollectionContext,
    baselineContext: CollectionContext? = nil,
    compatibility: CollectionFileCompatibilityMetadata? = .init(
        sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
        migrationPath: [.currentSchemaV2],
        warnings: [],
        usedDefinitionFallback: false,
        writeBackAllowed: true,
        writeBackReason: .allowed,
    ),
) -> FileManagerContentState {
    var state = FileManagerContentState()
    state.entryViewLayout.isCollectionMode = true
    state.collection.collectionSession.phase = .opened(
        kind: .hydratedSnapshot,
        base: .stale,
        inflight: .refreshingHydratedSnapshot,
    )
    state.collection.collectionSession.document = .init(
        url: openedURL,
        name: openedURL.deletingPathExtension().lastPathComponent,
        compatibility: compatibility,
    )
    state.collection.collectionSession.metadata.baseline = baselineContext.map(CollectionBaseline.init(context:))
    state.collection.collectionContext = collectionContext
    state.composer.scopes = scopes
    state.composer.conditions = []
    state.composer.lastAcceptedFiltersRequestID = requestID
    state.composer.pendingSearchQuery = query
    return state
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

private func makeFiltersResponse(paths: [String]) -> VoyagerShared.SearchResponsePayload {
    VoyagerShared.SearchResponsePayload(
        itemCount: paths.count,
        appliedFilters: .init(scopes: ["/tmp"], conditions: []),
        items: paths.map { path in
            .object(["fullPath": .string(path)])
        },
        error: nil,
    )
}

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

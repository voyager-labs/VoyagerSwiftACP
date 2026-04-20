import ComposableArchitecture
import Foundation
@testable import Voyager
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
            $0.collectionSession.isRefreshingHydratedSnapshot = false
            $0.collectionSession.isWritingBackRefreshedSnapshot = true
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertEqual(saved?.url, url)
        XCTAssertEqual(saved?.file.snapshot?.items, [.string("/tmp/report.txt")])
        XCTAssertEqual(saved?.file.snapshotMeta?.itemCount, 1)
        XCTAssertFalse(store.state.collectionSession.isWritingBackRefreshedSnapshot)
        XCTAssertFalse(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.staleReason)
        XCTAssertNotNil(store.state.collectionSession.lastRefreshAt)
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
            $0.collectionSession.isRefreshingHydratedSnapshot = false
            $0.collectionSession.isWritingBackRefreshedSnapshot = false
        }
        await store.finish()

        XCTAssertFalse(store.state.collectionSession.isRefreshingHydratedSnapshot)
        XCTAssertFalse(store.state.collectionSession.isWritingBackRefreshedSnapshot)
        XCTAssertTrue(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.lastRefreshAt)
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
            $0.collectionSession.isRefreshingHydratedSnapshot = false
            $0.collectionSession.isWritingBackRefreshedSnapshot = false
        }
        await store.finish()

        let saved = await recorder.last()
        XCTAssertNil(saved)
        XCTAssertFalse(store.state.collectionSession.isRefreshingHydratedSnapshot)
        XCTAssertFalse(store.state.collectionSession.isWritingBackRefreshedSnapshot)
        XCTAssertTrue(store.state.collectionSession.isStale)
        XCTAssertNil(store.state.collectionSession.lastRefreshAt)
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
                )
            },
        )
        $0.userDefaultsClient = .testValue
        $0.collectionStalenessClient = .testValue
    }
}

private func makeRefreshingState(
    requestID: UUID,
    openedURL: URL,
    query: String,
    scopes: [String],
    collectionContext: CollectionContext,
    baselineContext: CollectionContext? = nil,
) -> FileManagerContentState {
    var state = FileManagerContentState()
    state.entryViewLayout.isCollectionMode = true
    state.collectionSession.isRefreshingHydratedSnapshot = true
    state.collectionSession.isStale = true
    state.collectionSession.staleReason = .snapshotHydratedOnOpen
    state.collectionSession.didHydrateSnapshotOnOpen = true
    state.collectionSession.openedURL = openedURL
    state.collectionSession.openedName = openedURL.deletingPathExtension().lastPathComponent
    state.collectionSession.baseline = baselineContext.map(CollectionBaseline.init(context:))
    state.collectionContext = collectionContext
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

private func makeFiltersResponse(paths: [String]) -> SearchResponsePayload {
    SearchResponsePayload(
        itemCount: paths.count,
        appliedFilters: .init(scopes: ["/tmp"], conditions: []),
        items: paths.map { path in
            .object(["fullPath": .string(path)])
        },
        error: nil,
    )
}

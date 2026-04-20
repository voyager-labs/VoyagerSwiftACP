import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class CollectionReopenStaleTests: XCTestCase {
    func testOpenCollectionFileRestoresStaleStateFromStalenessClient() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = VoyagerCollectionFile(
            id: "id",
            name: "sample",
            createdAt: .init(timeIntervalSince1970: 1),
            updatedAt: .init(timeIntervalSince1970: 2),
            query: "",
            scopes: ["/tmp/voyager"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeOpenCollectionStore(
            file: file,
            openedURL: url,
            stalenessClient: stalenessClient,
        )
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case .navigation(.internal(.collectionFileLoaded(.success))) = action else {
                return false
            }
            return store.state.content.collectionSession.isStale
        }
        await store.finish()
    }

    func testCollectionFileLoadedRestoresStaleStateFromStalenessClient() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = VoyagerCollectionFile(
            id: "id",
            name: "sample",
            createdAt: .init(timeIntervalSince1970: 1),
            updatedAt: .init(timeIntervalSince1970: 2),
            query: "",
            scopes: ["/tmp/voyager"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeDefinitionOnlyStore(openedURL: url, stalenessClient: stalenessClient)
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(makeCollectionLoadResult(
            file,
            sourceSchemaVersion: nil,
        )))))) {
            $0.content.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
            $0.content.composer.isPresented = false
            $0.content.composer.pendingSearchQuery = nil
            $0.content.composer.text = ""
            $0.content.composer.scopes = ["/tmp/voyager"]
            $0.content.composer.conditions = []
            $0.content.collectionSession.baseline = .init(
                context: .init(query: "", scopes: ["/tmp/voyager"], conditions: []),
            )
        }

        XCTAssertTrue(store.state.content.collectionSession.isStale)
        XCTAssertNotEqual(store.state.content.collectionSession.openKind, .hydratedSnapshot)
        XCTAssertFalse(store.state.content.shouldRefreshOnOpen)
        await assertCollectionModeNavigation(store: store)
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionMode)
        await store.finish()
    }

    func testOpenStaleCollectionDoesNotAutoSearch() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = VoyagerCollectionFile(
            id: "id",
            name: "sample",
            createdAt: .init(timeIntervalSince1970: 1),
            updatedAt: .init(timeIntervalSince1970: 2),
            query: "report",
            scopes: ["/tmp/voyager"],
            conditions: [],
            snapshot: nil,
            snapshotMeta: nil,
            appVersion: nil,
        )

        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeOpenCollectionStore(
            file: file,
            openedURL: url,
            stalenessClient: stalenessClient,
        )
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case .navigation(.internal(.collectionFileLoaded(.success))) = action else {
                return false
            }
            return store.state.content.collectionSession.isStale
        }
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        await store.finish()
    }

    func testOpenStaleDefinitionOnlyCollectionDoesNotAutoSearch() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = makeDefinitionOnlyCollectionFile(query: "needle")
        let reopenContext = CollectionContext(query: "report", scopes: ["/tmp/voyager"], conditions: [])

        let stalenessClient = CollectionStalenessClient.live(userDefaultsClient: .testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeDefinitionOnlyStore(
            openedURL: url,
            stalenessClient: stalenessClient,
            reopenContext: reopenContext,
        )
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(makeCollectionLoadResult(
            file,
            sourceSchemaVersion: nil,
        )))))) {
            $0.content.collectionSession.phase = .opened(kind: .definition, base: .stale, inflight: .none)
            $0.content.composer.isPresented = false
            $0.content.composer.pendingSearchQuery = reopenContext.query
            $0.content.composer.text = reopenContext.query
            $0.content.composer.scopes = ["/tmp/voyager"]
            $0.content.composer.conditions = []
            $0.content.collectionSession.baseline = .init(
                context: reopenContext,
            )
        }

        XCTAssertTrue(store.state.content.collectionSession.isStale)
        XCTAssertNotEqual(store.state.content.collectionSession.openKind, .hydratedSnapshot)
        XCTAssertFalse(store.state.content.shouldRefreshOnOpen)
        await assertCollectionModeNavigation(store: store)
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        await store.finish()
    }

    func testNavigateToCollectionRestoresOpenedCompatibilityFromHistoryNavigation() async {
        let compatibility = CollectionFileCompatibilityMetadata(
            sourceSchemaVersion: 2,
            migrationPath: [.currentSchemaV2, .definitionFallbackFromMalformedSnapshot],
            warnings: [.droppedMalformedSnapshot],
            usedDefinitionFallback: true,
            writeBackAllowed: false,
            writeBackReason: .blockedDefinitionFallback,
        )
        let navigation = ContentPageCollectionNavigation(
            kind: .file(url: URL(fileURLWithPath: "/tmp/history.voycoll"), name: "history"),
            context: .init(query: "report", scopes: ["/tmp"], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
            compatibility: compatibility,
        )

        let store = TestStore(initialState: FileManagerWindowState()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .save },
                showCollectionOpenErrorAlert: { _, _ in },
            )
            $0.userDefaultsClient = .testValue
            $0.date = .constant(.distantFuture)
        }
        store.exhaustivity = .off

        await store.send(.navigation(.internal(.navigateToCollection(navigation)))) {
            $0.content.collectionSession.openedCompatibility = compatibility
            $0.content.collectionSession.baseline = .init(context: navigation.context)
            $0.content.collectionContext = navigation.context
            $0.content.composer.collectionContext = navigation.context
            $0.content.composer.pendingSearchQuery = "report"
            $0.content.composer.text = "report"
            $0.content.composer.scopes = ["/tmp"]
            $0.content.composer.conditions = []
        }

        XCTAssertEqual(store.state.content.collectionSession.openedCompatibility, compatibility)
    }
}

private func makeDefinitionOnlyCollectionFile(query: String) -> VoyagerCollectionFile {
    VoyagerCollectionFile(
        id: "id",
        name: "sample",
        createdAt: .init(timeIntervalSince1970: 1),
        updatedAt: .init(timeIntervalSince1970: 2),
        query: query,
        scopes: ["/tmp/voyager"],
        conditions: [],
        snapshot: nil,
        snapshotMeta: nil,
        appVersion: nil,
    )
}

@MainActor
private func makeDefinitionOnlyStore(
    openedURL: URL,
    stalenessClient: CollectionStalenessClient,
    reopenContext: CollectionContext? = nil,
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    var state = FileManagerWindowState()
    state.content.collectionSession.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
    state.content.collectionSession.openedURL = openedURL
    state.content.collectionSession.openedName = openedURL.deletingPathExtension().lastPathComponent
    state.content.collectionSession.captureReopenContext(reopenContext)

    return TestStore(initialState: state) {
        FileManagerFeature()
    } withDependencies: {
        $0.collectionAlertClient = .init(
            showUnsavedNavigationAlert: { .save },
            showCollectionOpenErrorAlert: { _, _ in },
        )
        $0.registryClient = .testValue
        $0.collectionStalenessClient = stalenessClient
        $0.userDefaultsClient = .testValue
        $0.date = .constant(.distantFuture)
    }
}

@MainActor
private func makeOpenCollectionStore(
    file: VoyagerCollectionFile,
    openedURL: URL,
    stalenessClient: CollectionStalenessClient,
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    var state = FileManagerWindowState()
    state.content.collectionSession.openedURL = openedURL
    state.content.collectionSession.openedName = openedURL.deletingPathExtension().lastPathComponent

    return TestStore(initialState: state) {
        FileManagerFeature()
    } withDependencies: {
        $0.collectionAlertClient = .init(
            showUnsavedNavigationAlert: { .save },
            showCollectionOpenErrorAlert: { _, _ in },
        )
        $0.collectionFileClient = .init(
            save: { _, _ in },
            load: { _ in makeCollectionLoadResult(file, sourceSchemaVersion: nil) },
        )
        $0.registryClient = .testValue
        $0.collectionStalenessClient = stalenessClient
        $0.userDefaultsClient = .testValue
        $0.date = .constant(.distantFuture)
    }
}

private func makeCollectionLoadResult(
    _ file: VoyagerCollectionFile,
    sourceSchemaVersion: Int?,
) -> CollectionFileLoadResult {
    VoyagerCollectionFileCompatibilityOwner.makeLoadResult(
        file: file,
        containerFormat: .package,
        sourceSchemaVersion: sourceSchemaVersion,
        warning: nil,
        usedDefinitionFallback: false,
    )
}

@MainActor
private func assertCollectionModeNavigation(
    store: TestStore<FileManagerWindowState, FileManagerWindowAction>,
) async {
    await store.receive {
        guard case .content(.internal(.requestNavigation(.internal(.setNavigationState(.collection))))) = $0 else {
            return false
        }
        return true
    }
    await store.receive {
        guard case .content(.internal(.applyNavigationState(.collection))) = $0 else {
            return false
        }
        return true
    }
    await store.receive {
        guard case .content(.entryViewLayout(.internal(.setCollectionMode(true)))) = $0 else {
            return false
        }
        return true
    }
}

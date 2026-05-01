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

        let stalenessClient = CollectionStalenessClient
            .live(userDefaultsClient: VoyagerShared.UserDefaultsClient.testValue)
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
            stalenessClient: stalenessClient,
        )
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case .navigation(.internal(.collectionFileLoaded(.success))) = action else {
                return false
            }
            return store.state.content.collectionSession.phase.isStale
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

        let stalenessClient = CollectionStalenessClient
            .live(userDefaultsClient: VoyagerShared.UserDefaultsClient.testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeDefinitionOnlyStore(stalenessClient: stalenessClient)
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
            $0.content.collectionSession.metadata.baseline = .init(
                context: .init(query: "", scopes: ["/tmp/voyager"], conditions: []),
            )
        }

        let isStale = store.state.content.collectionSession.phase.isStale
        let openKind = store.state.content.collectionSession.phase.openKind
        let isHydratedSnapshot = openKind == .hydratedSnapshot
        let shouldRefresh = shouldRefreshOnOpen(store.state.content.collectionSession)

        XCTAssertTrue(isStale)
        XCTAssertFalse(isHydratedSnapshot)
        XCTAssertFalse(shouldRefresh)
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

        let stalenessClient = CollectionStalenessClient
            .live(userDefaultsClient: VoyagerShared.UserDefaultsClient.testValue)
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
            stalenessClient: stalenessClient,
        )
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case .navigation(.internal(.collectionFileLoaded(.success))) = action else {
                return false
            }
            return store.state.content.collectionSession.phase.isStale
        }
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        await store.finish()
    }

    func testOpenStaleDefinitionOnlyCollectionDoesNotAutoSearch() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = makeDefinitionOnlyCollectionFile(query: "needle")
        let reopenContext = CollectionContext(query: "report", scopes: ["/tmp/voyager"], conditions: [])

        let stalenessClient = CollectionStalenessClient
            .live(userDefaultsClient: VoyagerShared.UserDefaultsClient.testValue)
        stalenessClient.upsertRecord(
            url.path,
            .init(
                definitionFingerprint: "",
                relevanceRoots: ["/tmp/voyager"],
                lastInvalidatedAt: .distantFuture,
            ),
        )

        let store = makeDefinitionOnlyStore(
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
            $0.content.collectionSession.metadata.baseline = .init(
                context: reopenContext,
            )
        }

        let isStale = store.state.content.collectionSession.phase.isStale
        let openKind = store.state.content.collectionSession.phase.openKind
        let isHydratedSnapshot = openKind == .hydratedSnapshot
        let shouldRefresh = shouldRefreshOnOpen(store.state.content.collectionSession)

        XCTAssertTrue(isStale)
        XCTAssertFalse(isHydratedSnapshot)
        XCTAssertFalse(shouldRefresh)
        await assertCollectionModeNavigation(store: store)
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        await store.finish()
    }

    func testNavigateToCollectionRestoresOpenedCompatibilityFromHistoryNavigation() async {
        let compatibility = CollectionFileCompatibilityMetadata(
            sourceSchemaVersion: CollectionFileSchemaVersion.snapshotBearingCurrent,
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
            $0.content.collectionSession.document = .init(
                url: URL(fileURLWithPath: "/tmp/history.voycoll"),
                name: "history",
                compatibility: compatibility,
            )
            $0.content.collectionSession.metadata.baseline = .init(context: navigation.context)
            $0.content.collectionContext = navigation.context
            $0.content.composer.collectionContext = navigation.context
            $0.content.composer.pendingSearchQuery = "report"
            $0.content.composer.text = "report"
            $0.content.composer.scopes = ["/tmp"]
            $0.content.composer.conditions = []
        }

        XCTAssertEqual(store.state.content.collectionSession.document?.compatibility, compatibility)
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
    stalenessClient: CollectionStalenessClient,
    reopenContext: CollectionContext? = nil,
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    var state = FileManagerWindowState()
    state.content.collectionSession.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
    state.content.collectionSession.document = .init(
        url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
        name: "sample",
        compatibility: nil,
    )
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
    stalenessClient: CollectionStalenessClient,
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    var state = FileManagerWindowState()
    state.content.collectionSession.document = .init(
        url: URL(fileURLWithPath: "/tmp/voyager/sample.voycoll"),
        name: "sample",
        compatibility: nil,
    )

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

@MainActor
private func shouldRefreshOnOpen(_ session: CollectionDocumentSessionState) -> Bool {
    session.phase.openKind == .hydratedSnapshot && session.phase.isStale && session.metadata.lastRefreshAt == nil
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

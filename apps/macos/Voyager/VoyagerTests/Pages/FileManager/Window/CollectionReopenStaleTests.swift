import ComposableArchitecture
import Foundation
@testable import Voyager
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

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(makeCollectionLoadResult(
            file,
            sourceSchemaVersion: nil,
        )))))) {
            $0.content.collectionSession.isOpening = false
            $0.content.collectionSession.isStale = true
            $0.content.collectionSession.staleReason = .invalidatedLocally
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
        XCTAssertEqual(store.state.content.collectionSession.staleReason, .invalidatedLocally)
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
        let file = VoyagerCollectionFile(
            id: "id",
            name: "sample",
            createdAt: .init(timeIntervalSince1970: 1),
            updatedAt: .init(timeIntervalSince1970: 2),
            query: "needle",
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

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(makeCollectionLoadResult(
            file,
            sourceSchemaVersion: nil,
        )))))) {
            $0.content.collectionSession.isOpening = false
            $0.content.collectionSession.isStale = true
            $0.content.collectionSession.staleReason = .invalidatedLocally
            $0.content.composer.isPresented = false
            $0.content.composer.pendingSearchQuery = "report"
            $0.content.composer.text = "report"
            $0.content.composer.scopes = ["/tmp/voyager"]
            $0.content.composer.conditions = []
            $0.content.collectionSession.baseline = .init(
                context: .init(query: "report", scopes: ["/tmp/voyager"], conditions: []),
            )
        }

        XCTAssertTrue(store.state.content.collectionSession.isStale)
        await assertCollectionModeNavigation(store: store)
        XCTAssertTrue(store.state.content.entryViewLayout.isCollectionMode)
        XCTAssertNil(store.state.content.composer.lastFiltersResponse)
        XCTAssertNil(store.state.content.composer.lastSearchResponse)
        await store.finish()
    }
}

@MainActor
private func makeDefinitionOnlyStore(
    openedURL: URL,
    stalenessClient: CollectionStalenessClient,
) -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
    var state = FileManagerWindowState()
    state.content.collectionSession.isOpening = true
    state.content.collectionSession.openedURL = openedURL
    state.content.collectionSession.openedName = openedURL.deletingPathExtension().lastPathComponent

    return TestStore(initialState: state) {
        FileManagerFeature()
    } withDependencies: {
        $0.collectionAlertClient = .init(
            showUnsavedNavigationAlert: { .save },
            showCollectionOpenErrorAlert: { _, _ in },
        )
        $0.registryClient = .testValue
        $0.collectionStalenessClient = stalenessClient
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
    }
}

private func makeCollectionLoadResult(
    _ file: VoyagerCollectionFile,
    sourceSchemaVersion: Int?,
) -> CollectionFileLoadResult {
    .init(
        file: file,
        containerFormat: .package,
        compatibility: .init(
            sourceSchemaVersion: sourceSchemaVersion,
            migrationPath: sourceSchemaVersion == VoyagerCollectionFile.currentSchemaVersion
                ? [.currentSchemaV2]
                : [.definitionOnlyV1, .currentSchemaV2],
            warnings: [],
            usedDefinitionFallback: false,
            writeBackAllowed: sourceSchemaVersion == VoyagerCollectionFile.currentSchemaVersion,
            writeBackReason: sourceSchemaVersion == VoyagerCollectionFile.currentSchemaVersion
                ? .allowed
                : .blockedLegacyVersionUpgrade,
        ),
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

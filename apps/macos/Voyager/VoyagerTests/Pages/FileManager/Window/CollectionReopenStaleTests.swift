import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class CollectionReopenStaleTests: XCTestCase {
    func testOpenCollectionFileRestoresStaleStateFromStalenessClient() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = VoyagerCollectionFile(
            schemaVersion: 1,
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
            schemaVersion: 1,
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

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(file))))) {
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
        await store.finish()
    }

    func testOpenStaleCollectionDoesNotAutoSearch() async {
        let url = URL(fileURLWithPath: "/tmp/voyager/sample.voycoll")
        let file = VoyagerCollectionFile(
            schemaVersion: 1,
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
            schemaVersion: 1,
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

        await store.send(.navigation(.internal(.collectionFileLoaded(.success(file))))) {
            $0.content.collectionSession.isOpening = false
            $0.content.collectionSession.isStale = true
            $0.content.collectionSession.staleReason = .invalidatedLocally
            $0.content.composer.isPresented = false
            $0.content.composer.pendingSearchQuery = "needle"
            $0.content.composer.text = ""
            $0.content.composer.scopes = ["/tmp/voyager"]
            $0.content.composer.conditions = []
            $0.content.collectionSession.baseline = .init(
                context: .init(query: "needle", scopes: ["/tmp/voyager"], conditions: []),
            )
        }

        XCTAssertTrue(store.state.content.collectionSession.isStale)
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
            load: { _ in file },
        )
        $0.registryClient = .testValue
        $0.collectionStalenessClient = stalenessClient
    }
}

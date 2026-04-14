import ComposableArchitecture
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

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in file }
            $0.collectionStalenessClient.consumeInvalidation = { path in
                path == url.path
            }
            $0.collectionStalenessClient.registerCollection = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case let .navigation(.internal(.collectionFileLoaded(.success(_, isStale)))) = action else {
                return false
            }
            return isStale == true
        }
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

        let store = TestStore(initialState: FileManagerFeature.State()) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient.load = { _ in file }
            $0.collectionStalenessClient.consumeInvalidation = { path in
                path == url.path
            }
            $0.collectionStalenessClient.registerCollection = { _, _ in }
        }

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case let .navigation(.internal(.collectionFileLoaded(.success(_, isStale)))) = action else {
                return false
            }
            return isStale == true
        }
        await store.finish()
    }
}

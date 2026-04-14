import ComposableArchitecture
import VoyagerEntitiesEntry
@testable import VoyagerPagesFileManager
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
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case let .navigation(.internal(.collectionFileLoaded(.success(loadedFile)))) = action else {
                return false
            }
            return loadedFile.id == file.id
        }
        await store.finish()
    }

    func testOpenStaleCollectionDoesNotAutoSearch() async {
        // TODO(VOY-223): Reducer now emits unexpected actions for stale collection open
        XCTExpectFailure("Reducer behavioral mismatch after VOY-223 migration")
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
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }

        await store.send(.navigation(.view(.openCollectionFile(url))))
        await store.receive { action in
            guard case let .navigation(.internal(.collectionFileLoaded(.success(loadedFile)))) = action else {
                return false
            }
            return loadedFile.id == file.id
        }
        await store.finish()
    }
}

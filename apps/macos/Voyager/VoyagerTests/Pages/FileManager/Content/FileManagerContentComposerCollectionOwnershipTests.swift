import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerShared
import XCTest

@MainActor
final class FileManagerComposerOwnershipTests: XCTestCase {
    func testSearchSuccessSendsSetCollectionModeBeforeApplyCollectionSearchPaths() async {
        let requestID = UUID()
        let items: [VoyagerShared.JSONValue] = [
            .object(["fullPath": .string("/tmp/voyager/file1.txt")]),
            .object(["fullPath": .string("/tmp/voyager/file2.txt")]),
        ]

        let store = makeSearchStore(requestID: requestID, items: items)

        await sendSearchSuccess(store: store, requestID: requestID, items: items)
        await assertSearchSuccessSequence(store: store)
    }

    func testSearchSuccessAcceptsStringPathItems() async {
        let requestID = UUID()
        let items: [VoyagerShared.JSONValue] = [
            .string("/tmp/voyager/file1.txt"),
            .string("/tmp/voyager/file2.txt"),
        ]

        let store = makeSearchStore(requestID: requestID, items: items)

        await sendSearchSuccess(store: store, requestID: requestID, items: items)
        await assertSearchSuccessSequence(
            store: store,
            expectedPaths: ["/tmp/voyager/file1.txt", "/tmp/voyager/file2.txt"],
        )
    }

    func testClearCollectionModeSendsClearCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])
        initialState.collectionSession.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        initialState.navigation.navigationState = .collection(
            ContentPageCollectionNavigation(
                kind: .temporary,
                context: .init(query: "test", scopes: [], conditions: []),
                sortKey: .name,
                sortOrder: .ascending,
                viewLayout: .list,
            ),
        )

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setText(""))))

        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setNavigationState))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setPendingNavigation(nil)))) = action
            else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .internal(.syncComposerCollectionState) = action else { return false }
            return true
        }
    }

    func testSyncComposerCollectionStateReadsFromCanonicalSource() {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true

        state.syncComposerCollectionState()

        XCTAssertTrue(
            state.composer.isCollectionMode,
            "syncComposerCollectionState must read from entryViewLayout.isCollectionMode (canonical)",
        )
    }

    func testCanSaveCollectionReadsFromCanonicalSource() {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true
        state.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])

        XCTAssertTrue(
            state.canSaveCollection,
            "canSaveCollection must read from entryViewLayout.isCollectionMode (canonical)",
        )
    }

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }

    private func makeSearchStore(
        requestID: UUID,
        items _: [VoyagerShared.JSONValue],
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var initialState = makeInitialState()
        initialState.composer.pendingSearchQuery = "test query"
        initialState.composer.activeFiltersRequestID = requestID
        initialState.composer.lastAcceptedFiltersRequestID = requestID

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
        store.exhaustivity = .off
        return store
    }

    private func sendSearchSuccess(
        store: TestStore<FileManagerContentState, FileManagerContentAction>,
        requestID: UUID,
        items: [VoyagerShared.JSONValue],
    ) async {
        await store.send(
            FileManagerContentAction.composer(
                ComposerAction.filtersResponse(
                    requestID,
                    .success(VoyagerShared.SearchResponsePayload(
                        itemCount: items.count,
                        items: items,
                    )),
                ),
            ),
        )
    }

    private func assertSearchSuccessSequence(
        store: TestStore<FileManagerContentState, FileManagerContentAction>,
        expectedPaths: [String]? = nil,
    ) async {
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.appendBackHistory))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.clearForwardHistory))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.internal(.setCollectionMode(true))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryViewLayout(.internal(.applyCollectionSearchPaths(paths, _))) = action else {
                return false
            }
            return expectedPaths.map { paths == $0 } ?? true
        }
        await store.receive { action in
            guard case .delegate(.composerCollectionSearchSucceeded) = action else { return false }
            return true
        }
    }
}

import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerContentComposerCollectionOwnershipTests: XCTestCase {
    func testSearchSuccessSendsSetCollectionModeBeforeApplyCollectionSearchPaths() async {
        let requestID = UUID()
        let items: [VoyagerShared.JSONValue] = [
            .object(["fullPath": .string("/tmp/voyager/file1.txt")]),
            .object(["fullPath": .string("/tmp/voyager/file2.txt")]),
        ]

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
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
        store.exhaustivity = .off

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

        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.appendBackHistory))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.clearForwardHistory))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .internal(.requestNavigation(.internal(.setNavigationState(.collection)))) = action
            else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.internal(.setCollectionMode(true))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.internal(.applyCollectionSearchPaths)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .delegate(.composerCollectionSearchSucceeded) = action else { return false }
            return true
        }
    }

    func testClearCollectionModeSendsClearCollectionPresentation() async {
        var initialState = makeInitialState()
        initialState.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])
        initialState.collectionSession.isOpening = true
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
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient.testValue
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
}

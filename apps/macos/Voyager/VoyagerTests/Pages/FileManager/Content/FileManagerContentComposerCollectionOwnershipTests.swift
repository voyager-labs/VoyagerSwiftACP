import ComposableArchitecture
import Foundation
@testable import Voyager
@testable import VoyagerPagesFileManager
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
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

    func testFiltersSuccessPreservesExistingCollectionQueryWhenPendingQueryIsNil() async {
        let requestID = UUID()
        let items: [VoyagerShared.JSONValue] = [
            .object(["fullPath": .string("/tmp/voyager/file1.txt")]),
        ]

        var initialState = makeInitialState()
        let context = CollectionContext(
            query: "kind:image",
            scopes: ["/tmp/voyager"],
            includeSubfolders: true,
            conditions: [],
        )
        initialState.collection.collectionContext = context
        initialState.composer.collectionContext = context
        initialState.composer.pendingSearchQuery = nil
        initialState.composer.activeFiltersRequestID = requestID
        initialState.composer.lastAcceptedFiltersRequestID = requestID
        initialState.composer.scopeEditor.selection = .fromLegacyScopes(["/tmp/voyager"])
        initialState.composer.scopeEditor.includeSubfolders = false

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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
            guard case let .collection(.searchSucceeded(context, _, _, _)) = action else {
                return false
            }
            return context.query == "kind:image"
                && context.scopes == ["/tmp/voyager"]
                && context.includeSubfolders == false
        }
    }

    func testClearCollectionModeResetsComposerAfterClearingPresentation() async {
        var initialState = makeInitialState()
        initialState.collection.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])
        initialState.collection.collectionSession.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
        initialState.entryViewLayout.isCollectionMode = true
        initialState.composer.isCollectionMode = true
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
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.internal(.clearCollectionMode))

        await store.receive { action in
            guard case .composer(.internal(.clearPendingSearchQuery)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .collection(.sessionResetRequested) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .composer(.internal(.resetComposerAndSync(_, _, _, isCollectionMode))) = action else {
                return false
            }
            return !isCollectionMode
        }

        XCTAssertFalse(store.state.entryViewLayout.isCollectionMode)
        XCTAssertFalse(store.state.composer.isCollectionMode)
    }

    func testComposerOpenSkipsSeedingWhenNavigationIsNotFolder() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .recents
        initialState.composer.isPresented = false

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

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true))))
    }

    func testComposerOpenSeedsCurrentPathThroughBridgeAction() async {
        var initialState = makeInitialState()
        initialState.composer.isPresented = false

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

        await store.send(FileManagerContentAction.composer(.view(.setPresented(true))))

        await store.receive { action in
            guard case let .composer(.internal(.scopeEditorSeedCurrentPath(path))) = action else {
                return false
            }
            return path == "/tmp/voyager"
        }
    }

    func testSyncComposerCollectionStatePreservesPendingScopeRuleWhileEditorIsPresented() {
        var state = makeInitialState()
        let context = CollectionContext(
            query: "",
            scopes: ["/tmp/voyager"],
            includeSubfolders: true,
            conditions: [],
        )
        state.collection.collectionContext = context
        state.composer.collectionContext = context
        state.composer.scopeEditor.isPresented = true
        state.composer.scopeEditor.selection = .explicit(
            bases: [ComposerScopeBase(path: "/tmp/voyager")],
            exceptions: [],
        )
        state.composer.scopeEditor.committedSelection = state.composer.scopeEditor.selection
        state.composer.scopeEditor.includeSubfolders = false
        state.composer.scopeEditor.committedIncludeSubfolders = true

        state.syncComposerCollectionState()

        XCTAssertFalse(
            state.composer.scopeEditor.includeSubfolders,
            "syncComposerCollectionState must not overwrite an uncommitted scope rule while editing",
        )
        XCTAssertTrue(
            state.composer.scopeEditor.committedIncludeSubfolders,
            "syncComposerCollectionState must preserve the committed scope rule baseline while editing",
        )
    }

    func testCanSaveCollectionReadsFromCanonicalSource() {
        var state = makeInitialState()
        state.entryViewLayout.isCollectionMode = true
        state.collection.collectionContext = CollectionContext(query: "test", scopes: [], conditions: [])

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
            $0.date = .constant(Date(timeIntervalSince1970: 1_234_567_890))
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

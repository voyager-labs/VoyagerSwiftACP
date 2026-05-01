import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerShared
import XCTest

@MainActor
final class FileManagerComposerCloseOwnershipTests: XCTestCase {
    func testComposerCloseWhileScopeEditorOpenDismissesScopeEditorFirst() async {
        let store = makeStore { state in
            state.composer.isPresented = true
            state.composer.scopeEditor.isPresented = true
        }

        await store.send(FileManagerContentAction.composer(.view(.setPresented(false)))) {
            $0.composer.isPresented = false
            $0.composer.scopeEditor.isPresented = false
            $0.composer.scopeEditor.queryText = ""
            $0.composer.scopeEditor.listState = .defaultCandidates
            $0.composer.scopeEditor.candidateItems = []
            $0.composer.scopeEditor.editingPath = nil
            $0.composer.scopeEditor.entryMode = .add
        }

        await store.receive { action in
            guard case .collection(.openSearchPresentationCancelled) = action else { return false }
            return true
        }
    }

    func testComposerCloseWhileScopeEditorOpenSubmitsSearchForQueryOnlyPendingScopeChange() async {
        let store = makeStore { state in
            state.composer.isPresented = true
            state.composer.scopeEditor.isPresented = true
            state.composer.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/tmp/voyager")],
                exceptions: [],
            )
            state.composer.scopeEditor.committedSelection = state.composer.scopeEditor.selection
            state.composer.pendingSearchQuery = "kind:image"
            state.composer.scopes = ["/tmp/voyager", "/tmp/downloads"]
            state.composer.scopeEditor.selection = .explicit(
                bases: [
                    ComposerScopeBase(path: "/tmp/voyager"),
                    ComposerScopeBase(path: "/tmp/downloads"),
                ],
                exceptions: [],
            )
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(false)))) {
            $0.composer.isPresented = false
            $0.composer.pendingSearchQuery = "kind:image"
        }

        await store.receive { action in
            guard case .composer(.view(.scopeEditorSetPresented(false))) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case .composer(.view(.submit)) = action else { return false }
            return true
        }

        XCTAssertTrue(store.state.composer.hasSubmittedInSession)
        XCTAssertTrue(store.state.composer.isLoadingSearch)
        XCTAssertFalse(store.state.composer.isLoadingFilters)
        XCTAssertEqual(
            store.state.composer.submittedSearchFilters,
            VoyagerShared.SearchFiltersPayload(
                scopes: ["/tmp/voyager", "/tmp/downloads"],
                includeSubfolders: true,
                conditions: [],
            ),
        )
        XCTAssertNotNil(store.state.composer.activeSearchRequestID)
        XCTAssertNil(store.state.composer.activeFiltersRequestID)
        XCTAssertNil(store.state.composer.lastAcceptedSearchRequestID)
        XCTAssertNil(store.state.composer.lastAcceptedFiltersRequestID)
        XCTAssertNil(store.state.composer.lastFiltersResponse)
        XCTAssertEqual(store.state.composer.text, "")
    }

    func testOpenSearchPresentationCancelledDoesNotSyncComposerScopeRuleWhileFiltersInFlight() async {
        let store = makeStore { state in
            state.collectionContext = CollectionContext(
                query: "kind:image",
                scopes: ["/tmp/voyager"],
                includeSubfolders: true,
                conditions: [],
            )
            state.composer.collectionContext = state.collectionContext
            state.composer.scopeEditor.selection = .explicit(
                bases: [ComposerScopeBase(path: "/tmp/voyager")],
                exceptions: [],
            )
            state.composer.scopeEditor.includeSubfolders = false
            state.composer.isFilteringInFlight = true
        }

        await store.send(.collection(.openSearchPresentationCancelled))

        XCTAssertFalse(store.state.composer.scopeEditor.includeSubfolders)
        XCTAssertEqual(store.state.composer.collectionContext?.includeSubfolders, true)
    }

    func testComposerCloseWhileFilteringClosesScopeEditorWithoutCancellingFilters() async {
        let store = makeStore { state in
            state.composer.isPresented = true
            state.composer.scopeEditor.isPresented = true
            state.composer.isFilteringInFlight = true
            state.composer.isLoadingFilters = true
            state.composer.activeFiltersRequestID = UUID()
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(.view(.setPresented(false)))) {
            $0.composer.isPresented = false
            $0.composer.scopeEditor.isPresented = false
            $0.composer.scopeEditor.queryText = ""
            $0.composer.scopeEditor.listState = .defaultCandidates
            $0.composer.scopeEditor.candidateItems = []
            $0.composer.scopeEditor.editingPath = nil
            $0.composer.scopeEditor.entryMode = .add
            $0.composer.isFilteringInFlight = true
            $0.composer.isLoadingFilters = true
        }

        XCTAssertNotNil(store.state.composer.activeFiltersRequestID)
    }

    private func makeStore(
        mutate: (inout FileManagerContentState) -> Void,
    ) -> TestStore<FileManagerContentState, FileManagerContentAction> {
        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        mutate(&initialState)
        return TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = CollectionAlertClient.testValue
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
    }
}

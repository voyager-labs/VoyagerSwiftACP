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
/// FileManager composer 실패 경로에서 collection 경보/모달 핸들링 경계를 검증한다.
final class ComposerFeedbackGuardrailTests: XCTestCase {
    /// testInteractiveComposerFailureDoesNotInvokeCollectionAlert 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testInteractiveComposerFailureDoesNotInvokeCollectionAlert() async {
        let alerts = CollectionAlertRecorder()
        let requestID = UUID()
        var initialState = FileManagerContentState()
        initialState.composer.pendingSearchQuery = "kind:image"
        initialState.composer.isLoadingSearch = true
        initialState.composer.activeSearchRequestID = requestID
        initialState.composer.queryRenderPhase = .searching

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .cancel },
                showCollectionOpenErrorAlert: { title, message in
                    await alerts.record(title: title, message: message)
                },
            )
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(ComposerAction.searchResponse(
            requestID,
            .failure(GuardrailError.sample),
        )))
        await store.receive { action in
            guard case .delegate(.composerCollectionSearchFailed) = action else { return false }
            return true
        }
        await Task.yield()

        XCTAssertEqual(alerts.count(), 0)
        XCTAssertFalse(store.state.collection.collectionSession.phase.isOpening)
        XCTAssertEqual(
            store.state.composer.transientFeedback?.message,
            ComposerQueryFeedbackPolicy.executionFailureMessage,
        )
    }

    /// testCollectionOpenFailureStillShowsModalAlertAndRollsBack 시나리오가 FileManager 계약을 위반하지 않음을 검증한다.
    func testCollectionOpenFailureStillShowsModalAlertAndRollsBack() async {
        let alerts = CollectionAlertRecorder()
        let requestID = UUID()
        let initialState = makeCollectionOpeningState(requestID: requestID)

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = VoyagerShared.UserDefaultsClient.testValue
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .cancel },
                showCollectionOpenErrorAlert: { title, message in
                    await alerts.record(title: title, message: message)
                },
            )
            $0.fileManagerClient = VoyagerShared.FileManagerClient.testValue
            $0.thumbnailGeneratorClient = VoyagerShared.ThumbnailGeneratorClient.testValue
            $0.entryThumbnailCacheClient = EntryThumbnailCacheClient.testValue
            $0.notificationCenterClient = VoyagerShared.NotificationCenterClient.testValue
        }
        store.exhaustivity = .off

        await store.send(FileManagerContentAction.composer(ComposerAction.searchResponse(
            requestID,
            .failure(GuardrailError.sample),
        )))
        await assertCollectionOpenFailureRollback(store: store)
        await Task.yield()

        XCTAssertEqual(alerts.count(), 1)
        XCTAssertEqual(alerts.lastTitle(), "Unable to Run Collection Search")
        XCTAssertFalse(store.state.collection.collectionSession.phase.isOpening)
        XCTAssertNil(store.state.collection.collectionSession.document?.name)
        XCTAssertNil(store.state.collection.collectionSession.document?.url)
        XCTAssertNil(store.state.collection.collectionSession.metadata.baseline)
        XCTAssertFalse(store.state.entryViewLayout.isCollectionMode)
        XCTAssertNil(store.state.collection.collectionContext)
    }
}

@MainActor
private func assertCollectionOpenFailureRollback(
    store: TestStore<FileManagerContentState, FileManagerContentAction>,
) async {
    await store.receive { action in
        guard case .internal(.requestNavigation(.internal(.rollbackBackHistoryOnce))) = action else { return false }
        return true
    }
    await store.receive { action in
        guard case .internal(.requestNavigation(.internal(.setNavigationState(.folder("/tmp"))))) = action
        else { return false }
        return true
    }
    await store.receive { action in
        guard case .internal(.requestNavigation(.internal(.setPendingNavigation(nil)))) = action
        else { return false }
        return true
    }
    await store.receive { action in
        guard case .entryViewLayout(.internal(.setCollectionMode(false))) = action else { return false }
        return true
    }
    await store.receive { action in
        guard case .entryViewLayout(.internal(.clearCollectionPresentation)) = action else { return false }
        return true
    }
    await store.receive { action in
        guard case .delegate(.composerCollectionSearchFailed) = action else { return false }
        return true
    }
}

@MainActor
private func makeCollectionOpeningState(requestID: UUID) -> FileManagerContentState {
    var state = FileManagerContentState()
    state.collection.collectionSession.phase = .reopening(kind: .definition, base: .ready, inflight: .none)
    state.collection.collectionSession.document = .init(
        url: URL(fileURLWithPath: "/tmp/saved-search.voyager-collection"),
        name: "Saved Search",
        compatibility: nil,
    )
    state.composer.pendingSearchQuery = "kind:image"
    state.composer.isLoadingSearch = true
    state.composer.activeSearchRequestID = requestID
    state.composer.queryRenderPhase = .searching
    state.navigation.navigationState = .collection(
        ContentPageCollectionNavigation(
            kind: .file(
                url: URL(fileURLWithPath: "/tmp/saved-search.voyager-collection"),
                name: "Saved Search",
            ),
            context: .init(query: "kind:image", scopes: ["/tmp"], conditions: []),
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .grid,
        ),
    )
    state.navigation.titlePath = "/tmp"
    state.entryViewLayout.isCollectionMode = true
    state.syncComposerCollectionState()
    return state
}

private final class CollectionAlertRecorder: @unchecked Sendable {
    private var calls: [(title: String, message: String)] = []

    func record(title: String, message: String) {
        calls.append((title, message))
    }

    func count() -> Int {
        calls.count
    }

    func lastTitle() -> String? {
        calls.last?.title
    }
}

private enum GuardrailError: LocalizedError {
    case sample

    var errorDescription: String? {
        "HELPER_UNAVAILABLE: disconnected"
    }
}

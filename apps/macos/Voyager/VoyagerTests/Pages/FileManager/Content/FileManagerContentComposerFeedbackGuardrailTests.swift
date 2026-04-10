import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class ComposerFeedbackGuardrailTests: XCTestCase {
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
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .cancel },
                showCollectionOpenErrorAlert: { title, message in
                    await alerts.record(title: title, message: message)
                },
            )
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.composer(.searchResponse(requestID, .failure(GuardrailError.sample))))
        await store.receive(.delegate(.composerCollectionSearchFailed))
        await Task.yield()

        await XCTAssertEqual(alerts.count(), 0)
        XCTAssertFalse(store.state.collectionSession.isOpening)
        XCTAssertEqual(
            store.state.composer.transientFeedback?.message,
            ComposerQueryFeedbackPolicy.executionFailureMessage,
        )
    }

    func testCollectionOpenFailureStillShowsModalAlertAndRollsBack() async {
        let alerts = CollectionAlertRecorder()
        let requestID = UUID()
        let initialState = makeCollectionOpeningState(requestID: requestID)

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        } withDependencies: {
            $0.userDefaultsClient = .testValue
            $0.collectionAlertClient = .init(
                showUnsavedNavigationAlert: { .cancel },
                showCollectionOpenErrorAlert: { title, message in
                    await alerts.record(title: title, message: message)
                },
            )
            $0.fileManagerClient = .testValue
            $0.thumbnailGeneratorClient = .testValue
            $0.entryThumbnailCacheClient = .testValue
            $0.notificationCenterClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.composer(.searchResponse(requestID, .failure(GuardrailError.sample))))
        await store.receive(.internal(.requestNavigation(.internal(.rollbackBackHistoryOnce))))
        await store.receive(.internal(.requestNavigation(.internal(.setNavigationState(.folder(path: "/tmp"))))))
        await store.receive(.internal(.requestNavigation(.internal(.setPendingNavigation(nil)))))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.setCollectionMode(false)))))
        await store.receive(.entryViewLayout(.entryOperations(.loading(.clearCollectionItems))))
        await store.receive(.delegate(.composerCollectionSearchFailed))
        await Task.yield()

        await XCTAssertEqual(alerts.count(), 1)
        await XCTAssertEqual(alerts.lastTitle(), "Unable to Run Collection Search")
        XCTAssertEqual(store.state.collectionSession, .init())
        XCTAssertFalse(store.state.entryViewLayout.entryOperations.loadingContext.isCollectionMode)
        XCTAssertNil(store.state.collectionContext)
    }
}

private func makeCollectionOpeningState(requestID: UUID) -> FileManagerContentState {
    var state = FileManagerContentState()
    state.collectionSession.isOpening = true
    state.collectionSession.openedName = "Saved Search"
    state.collectionSession.openedURL = URL(fileURLWithPath: "/tmp/saved-search.voyager-collection")
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
    state.entryViewLayout.entryOperations.loadingContext.isCollectionMode = true
    state.syncComposerCollectionState()
    return state
}

private actor CollectionAlertRecorder {
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

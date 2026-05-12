import ComposableArchitecture
import VoyagerEntitiesCollection
@testable import VoyagerFeaturesContentPageNavigation
import VoyagerShared
import XCTest

@MainActor
final class ContentPageNavigationFeatureTests: XCTestCase {
    func testDirectNavigateToPathRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performNavigateToPath("/next"))) {
            $0.navigationState = .folder("/next")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .folder("/next"))))
        await store.receive(.delegate(.navigateToState(.folder("/next"))))
    }

    func testDirectShowRecentsRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performShowRecents)) {
            $0.navigationState = .recents
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .recents)))
        await store.receive(.delegate(.navigateToState(.recents)))
    }

    func testDirectShowTagRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performShowTag("work"))) {
            $0.navigationState = .tags("work")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .tags("work"))))
        await store.receive(.delegate(.navigateToState(.tags("work"))))
    }

    func testDirectShowComputerRecordsHistoryAndEmitsDelegatesInOrder() async {
        let store = makeStore(seedPath: "/seed")

        await store.send(.internal(.performShowComputer)) {
            $0.navigationState = .computer
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/seed"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/seed"), next: .computer)))
        await store.receive(.delegate(.navigateToState(.computer)))
    }

    func testBackThenForwardNavigationMovesHistoryAndEmitsResetBeforeNavigateForNonCollection() async {
        let store = makeStore(seedPath: "/a")

        await store.send(.internal(.performNavigateToPath("/b"))) {
            $0.navigationState = .folder("/b")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a"))]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/a"), next: .folder("/b"))))
        await store.receive(.delegate(.navigateToState(.folder("/b"))))

        await store.send(.internal(.performNavigateToPath("/c"))) {
            $0.navigationState = .folder("/c")
            $0.backHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/a")),
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/b")),
            ]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/b"), next: .folder("/c"))))
        await store.receive(.delegate(.navigateToState(.folder("/c"))))

        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = .folder("/b")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a"))]
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/c"))]
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/c"), next: .folder("/b"))))
        await store.receive(.delegate(.navigateToState(.folder("/b"))))

        await store.send(.internal(.performNavigation(.forward))) {
            $0.navigationState = .folder("/c")
            $0.backHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/a")),
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/b")),
            ]
            $0.forwardHistory = []
        }
        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/b"), next: .folder("/c"))))
        await store.receive(.delegate(.navigateToState(.folder("/c"))))
    }

    func testHistoryJumpFromBackHistoryRebalancesBackAndForward() async {
        var initial = ContentPageNavigationFeature.State()
        initial.seedInitialFolderPath("/d")
        initial.backHistory = [
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/a")),
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/b")),
            ContentPageNavigationHistorySnapshot(navigationState: .folder("/c")),
        ]
        initial.forwardHistory = []

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        await store.send(.internal(.performNavigation(.history(index: 1, isBackHistory: true)))) {
            $0.navigationState = .folder("/b")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a"))]
            $0.forwardHistory = [
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/d")),
                ContentPageNavigationHistorySnapshot(navigationState: .folder("/c")),
            ]
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/d"), next: .folder("/b"))))
        await store.receive(.delegate(.navigateToState(.folder("/b"))))
    }

    func testEnclosingDirectoryAppendsBackHistoryClearsForwardHistoryAndEmitsDelegatesInOrder() async {
        var initial = ContentPageNavigationFeature.State()
        initial.seedInitialFolderPath("/a/b")
        initial.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a/b/c"))]

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        await store.send(.internal(.performNavigation(.enclosingDirectory))) {
            $0.navigationState = .folder("/a")
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/a/b"))]
            $0.forwardHistory = []
        }

        await store.receive(.delegate(.resetComposer))
        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/a/b"), next: .folder("/a"))))
        await store.receive(.delegate(.navigateToState(.folder("/a"))))
    }

    func testHistoryNavigationToCollectionDoesNotEmitResetComposer() async {
        let collectionRoute = ContentPageNavigationRoute.collection(makeCollectionNavigation())

        var initial = ContentPageNavigationFeature.State()
        initial.seedInitialFolderPath("/folder")
        initial.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: collectionRoute)]

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        await store.send(.internal(.performNavigation(.back))) {
            $0.navigationState = collectionRoute
            $0.backHistory = []
            $0.forwardHistory = [ContentPageNavigationHistorySnapshot(navigationState: .folder("/folder"))]
        }

        await store.receive(.delegate(.logDAUNavigation(previous: .folder("/folder"), next: collectionRoute)))
        await store.receive(.delegate(.navigateToState(collectionRoute)))
    }

    func testPrepareCollectionFileOpenRecordsActualCurrentSnapshot() async {
        var initial = ContentPageNavigationFeature.State()
        initial.navigationState = .recents

        let store = TestStore(initialState: initial) {
            ContentPageNavigationFeature()
        }

        let url = URL(fileURLWithPath: "/folder/sample.voycoll")

        await store.send(.internal(.prepareCollectionFileOpen(url))) {
            $0.backHistory = [ContentPageNavigationHistorySnapshot(navigationState: .recents)]
            $0.forwardHistory = []
        }
    }

    func testHistoryIsTrimmedToTenEntries() async {
        let store = makeStore(seedPath: "/seed")
        store.exhaustivity = .off

        for index in 0 ..< 12 {
            await store.send(.internal(.performNavigateToPath("/p/\(index)")))
            await store.receive(.delegate(.resetComposer))
            await store.receive(\.delegate)
            await store.receive(\.delegate)
        }

        XCTAssertEqual(store.state.backHistory.count, 10)
        XCTAssertEqual(store.state.forwardHistory.count, 0)
        XCTAssertEqual(store.state.navigationState, .folder("/p/11"))

        XCTAssertEqual(store.state.backHistory.first?.navigationState, .folder("/p/1"))
        XCTAssertEqual(store.state.backHistory.last?.navigationState, .folder("/p/10"))

        await store.finish()
    }
}

@MainActor
private func makeStore(
    seedPath: String
) -> TestStore<ContentPageNavigationFeature.State, ContentPageNavigationFeature.Action> {
    var state = ContentPageNavigationFeature.State()
    state.seedInitialFolderPath(seedPath)
    return TestStore(initialState: state) {
        ContentPageNavigationFeature()
    }
}

private func makeCollectionNavigation() -> ContentPageCollectionNavigation {
    ContentPageCollectionNavigation(
        kind: .temporary,
        context: CollectionContext(query: "", scopes: [], conditions: []),
        sortKey: .name,
        sortOrder: .ascending,
        viewLayout: .list
    )
}

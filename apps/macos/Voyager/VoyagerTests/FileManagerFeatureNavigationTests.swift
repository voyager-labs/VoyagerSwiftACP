import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerFeatureNavigationTests: XCTestCase {
    func testGoBackMovesSnapshotToForwardHistory() async {
        var state = makeState(path: "/current")
        state.backHistory = [
            FileManagerFeature.HistoryEntry(
                navigationState: .folder("/previous"),
                sidebarItemName: nil,
                composerState: .init(),
            ),
        ]
        let store = makeStore(initialState: state)

        await store.send(.goBack)
        await store.receive(\.performNavigation)

        XCTAssertEqual(store.state.navigationState, .folder("/previous"))
        XCTAssertTrue(store.state.backHistory.isEmpty)
        XCTAssertEqual(store.state.forwardHistory.count, 1)
        XCTAssertEqual(store.state.forwardHistory.last?.navigationState, .folder("/current"))
    }

    func testGoForwardMovesSnapshotToBackHistory() async {
        var state = makeState(path: "/current")
        state.forwardHistory = [
            FileManagerFeature.HistoryEntry(
                navigationState: .folder("/next"),
                sidebarItemName: nil,
                composerState: .init(),
            ),
        ]
        let store = makeStore(initialState: state)

        await store.send(.goForward)
        await store.receive(\.performNavigation)

        XCTAssertEqual(store.state.navigationState, .folder("/next"))
        XCTAssertTrue(store.state.forwardHistory.isEmpty)
        XCTAssertEqual(store.state.backHistory.count, 1)
        XCTAssertEqual(store.state.backHistory.last?.navigationState, .folder("/current"))
    }

    func testChangeLayoutUpdatesListViewFlag() async {
        var state = makeState(path: "/current")
        state.entries.isListView = true
        let store = makeStore(initialState: state)

        await store.send(.changeLayout(.grid)) { state in
            state.viewLayout = .grid
            state.entries.isListView = false
        }
    }

    func testCollectionDirtyTracksLayoutChange() async {
        let context = CollectionContext(query: "Report", scopes: ["/tmp"], conditions: [])
        let baseline = FileManagerFeature.CollectionBaseline(
            context: context,
            sortKey: .name,
            sortOrder: .ascending,
            viewLayout: .list,
        )
        var state = makeState(path: "/current")
        state.entries.isCollectionMode = true
        state.collectionContext = context
        state.openedCollectionBaseline = baseline
        state.viewLayout = .list
        let store = makeStore(initialState: state)

        XCTAssertFalse(store.state.isOpenedCollectionDirty)
        XCTAssertFalse(store.state.canSaveCollection)

        await store.send(.changeLayout(.grid)) { state in
            state.viewLayout = .grid
            state.entries.isListView = false
        }

        XCTAssertTrue(store.state.isOpenedCollectionDirty)
        XCTAssertTrue(store.state.canSaveCollection)
    }

    func testGoBackPromptsUnsavedNavigationAlert() async {
        let alertClient = CollectionAlertClient(
            showUnsavedNavigationAlert: { .cancel },
            showCollectionOpenErrorAlert: { _, _ in },
        )

        var state = makeState(path: "/current")
        state.entries.isCollectionMode = true
        state.collectionContext = CollectionContext(query: "", scopes: [], conditions: [])
        state.backHistory = [
            FileManagerFeature.HistoryEntry(
                navigationState: .folder("/previous"),
                sidebarItemName: nil,
                composerState: .init(),
            ),
        ]

        let store = TestStore(initialState: state) {
            FileManagerFeature()
        } withDependencies: {
            $0.collectionFileClient = .testValue
            $0.entryClient = .testValue
            $0.collectionAlertClient = alertClient
            $0.fileManagerWindowClient = .testValue
            $0.registryClient = .testValue
            $0.sidebarClient = .testValue
            $0.undoManagerClient = .testValue
            $0.userDefaultsClient = .testValue
            $0.workspaceClient = .testValue
        }
        store.exhaustivity = .off

        await store.send(.goBack)
        await store.receive(
            .showUnsavedNavigationAlert(.back),
        )
        await store.receive(
            .unsavedNavigationAlertResponse(.back, .cancel),
        )
    }
}

@MainActor
private func makeStore(
    initialState: FileManagerFeature.State,
) -> TestStore<FileManagerFeature.State, FileManagerFeature.Action> {
    let store = TestStore(initialState: initialState) {
        FileManagerFeature()
    } withDependencies: {
        $0.collectionFileClient = .testValue
        $0.entryClient = .testValue
        $0.collectionAlertClient = .testValue
        $0.fileManagerWindowClient = .testValue
        $0.registryClient = .testValue
        $0.sidebarClient = .testValue
        $0.undoManagerClient = .testValue
        $0.userDefaultsClient = .testValue
        $0.workspaceClient = .testValue
    }
    store.exhaustivity = .off
    return store
}

@MainActor
private func makeState(path: String) -> FileManagerFeature.State {
    var state = FileManagerFeature.State()
    state.navigationState = .folder(path)
    state.titlePath = path
    return state
}

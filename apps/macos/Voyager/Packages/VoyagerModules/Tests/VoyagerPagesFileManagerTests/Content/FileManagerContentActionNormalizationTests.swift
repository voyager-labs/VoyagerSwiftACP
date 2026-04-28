import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
@testable import VoyagerPagesFileManager
import VoyagerShared
import VoyagerWidgetsEntryViewLayout
import XCTest

@MainActor
final class FileManagerContentActionNormalizationTests: XCTestCase {
    private let reducer = FileManagerContentFeature()

    private func makeInitialState() -> FileManagerContentState {
        var state = FileManagerContentState()
        state.navigation.seedInitialFolderPath("/tmp/voyager")
        return state
    }

    // MARK: - Action.ChildCases membership

    func testActionHasChildCases() async {
        let actions: [FileManagerContentAction] = [
            .view(.selectAllEntries),
            .view(.toggleShowHiddenFilesAndReload),
            .view(.handleKeyCommand(KeyCommand(
                keyCode: 36,
                modifiers: [],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
            ))),
            .view(.changeLayout(.list)),
            .internal(.applyNavigationState(.folder("/tmp"))),
            .internal(.saveScrollOffset(.zero, forPath: "/tmp")),
            .internal(.startObservingSystemNotifications),
            .internal(.stopObservingSystemNotifications),
            .internal(.systemAppDidBecomeActive),
            .internal(.syncComposerCollectionState),
            .delegate(.openPathInNewWindow("/tmp")),
            .delegate(.openPathInNewTab("/tmp")),
            .delegate(.closeWindow),
            .entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem)))),
            .entryViewLayout(.entryOperations(.lifecycle(.appDidBecomeActive))),
        ]
        for action in actions {
            _ = action
        }
    }

    // MARK: - selectAllEntries routes through entryViewLayout

    func testSelectAllEntriesRoutesToEntryViewLayout() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.view(.selectAllEntries))
        await store.receive { action in
            guard case .entryViewLayout(.internal(.applySelectAll)) = action else { return false }
            return true
        }
    }

    // MARK: - toggleShowHiddenFilesAndReload: navigation bridge handles reload

    func testToggleShowHiddenFilesAndReloadRoutesCorrectly() async {
        var initialState = makeInitialState()
        initialState.entryViewLayout.showHiddenFiles = false
        initialState.navigation.navigationState = .folder("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.view(.toggleShowHiddenFilesAndReload))
        await store.receive { action in
            guard case .entryViewLayout(.view(.toggleShowHiddenFiles)) = action else { return false }
            return true
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden)))) = action
            else { return false }
            return path == "/tmp/voyager" && showHidden == true
        }
    }

    // MARK: - entry operations actions route through EntryOperations bridge

    func testEntryOperationsLifecycleRoutesCorrectly() async {
        var initialState = makeInitialState()
        initialState.navigation.navigationState = .folder("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.lifecycle(.operationFinished(
            "/tmp/voyager/file.txt",
            .rename,
            .success(()),
        )))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(path, showHidden)))) = action
            else { return false }
            return path == "/tmp/voyager" && showHidden == false
        }
    }

    // MARK: - system notification routes through EntryOperations bridge

    func testSystemAppDidBecomeActiveRoutesToEntryOperations() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.internal(.systemAppDidBecomeActive))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.lifecycle(.appDidBecomeActive))) = action
            else { return false }
            return true
        }
    }

    // MARK: - EntryViewLayout delegate actions route through EntryOperations bridge

    func testEntryViewLayoutDelegateExecuteCommandRoutesCorrectly() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem)))))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.routing(.executeCommand))) = action else { return false }
            return true
        }
    }

    // MARK: - drop items delegate routes through EntryOperations bridge

    func testDropItemsToSidebarFolderRoutesToEntryOperations() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        let provider = NSItemProvider()
        let targetURL = URL(fileURLWithPath: "/tmp/dest")
        await store.send(.delegate(.dropItemsToSidebarFolder(providers: [provider], targetURL: targetURL)))
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.routing(.handleDrop))) = action else { return false }
            return true
        }
    }

    // MARK: - EntryOperations delegate routes navigation request

    func testEntryOperationsNavigateToPathRoutesToRequestNavigation() async {
        let store = TestStore(initialState: makeInitialState()) {
            reducer
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.entryOperations(.delegate(.navigateToPath("/tmp/new")))))
        await store.receive { action in
            guard case .internal(.requestNavigation) = action else { return false }
            return true
        }
    }
}

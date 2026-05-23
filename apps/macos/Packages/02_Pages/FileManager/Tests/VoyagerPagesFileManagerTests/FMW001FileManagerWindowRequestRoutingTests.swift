import ComposableArchitecture

import XCTest

@testable import VoyagerPagesFileManager

// FMW-001 (package-scoped): 단일 윈도우 명령 요청 라우팅
final class FMW001FileManagerWindowRequestRoutingTests: XCTestCase {
    // MARK: - FMW-001-toggleSidebar

    func test_sidebarToggleRequest_forwardsToSidebarReducer() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.toggleSidebar))
        store.receive(\.sidebar.view.setSidebarVisible)
    }

    func test_sidebarToggleRequest_repeatedToggle_isIdempotent() {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true

        let store = TestStore(
            initialState: initialState,
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.toggleSidebar))
        store.receive(\.sidebar.view.setSidebarVisible)

        store.send(.request(.toggleSidebar))
        store.receive(\.sidebar.view.setSidebarVisible)
    }

    // MARK: - FMW-001-navigation

    func test_navigationRequest_goBack_forwardsToNavigationReducer() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.goBack))
        store.receive(\.navigation.view.goBack)
    }

    func test_navigationRequest_goForward_forwardsToNavigationReducer() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.goForward))
        store.receive(\.navigation.view.goForward)
    }

    func test_navigationRequest_goToEnclosingDirectory_forwardsToNavigationReducer() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.goToEnclosingDirectory))
        store.receive(\.navigation.view.goToEnclosingDirectory)
    }

    // MARK: - FMW-001-selectionDependent

    func test_commandWithNoSelection_openSelectedItem_isNoOp() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.openSelectedItem))
    }

    func test_commandWithNoSelection_quickLookSelectedItem_isNoOp() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.quickLookSelectedItem))
    }

    // MARK: - FMW-001-isolation

    func test_commandRouting_doesNotMutateUnrelatedWindowState_navigation() {
        var initialState = FileManagerWindowState()
        initialState.sidebar.sidebarVisible = true
        initialState.sidebar.sidebarWidth = 250
        initialState.sidebar.isFavoritesCollapsed = true

        let store = TestStore(
            initialState: initialState,
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.goBack))
        store.receive(\.navigation.view.goBack)
    }

    func test_commandRouting_doesNotMutateUnrelatedWindowState_sidebarToggle() {
        var initialState = FileManagerWindowState()
        initialState.inspector.inspectorVisible = true

        let store = TestStore(
            initialState: initialState,
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.toggleSidebar))
        store.receive(\.sidebar.view.setSidebarVisible)
    }

    // MARK: - FMW-001-undoRedo

    func test_undoRedoRequest_undo_forwardsToEntryOperations() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.requestUndo))
        store.receive(\.content.entryViewLayout.entryOperations.undoRedo.requestUndo)
    }

    func test_undoRedoRequest_redo_forwardsToEntryOperations() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.requestRedo))
        store.receive(\.content.entryViewLayout.entryOperations.undoRedo.requestRedo)
    }

    // MARK: - FMW-001-composer

    func test_composerRequest_toggleComposer_forwardsToContentComposer() {
        let store = TestStore(
            initialState: FileManagerWindowState(),
        ) {
            FileManagerWindowCommandRoutingReducer()
        }

        store.send(.request(.toggleComposer))
        store.receive(\.content.composer.setPresented)
    }
}

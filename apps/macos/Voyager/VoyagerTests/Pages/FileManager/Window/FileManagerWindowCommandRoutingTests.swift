import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowCommandRoutingTests: XCTestCase {
    func testNewFolderCommandUsesCurrentNavigationPath() async {
        var initialState = FileManagerFeature.State()
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.content.entryViewLayout.entries = [
            .temporaryFolder(id: "/tmp/voyager/untitled folder", name: "untitled folder"),
        ]

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        } withDependencies: {
            $0.entryFileOpsClient = .previewValue
            $0.undoManagerClient = .init(
                registerUndo: { _, _, _, _ in },
                undo: { _ in },
                redo: { _ in },
            )
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.request(.newFolder))
        await store.receive {
            guard case let .content(.entryViewLayout(.entryOperations(.createNewFolder(parentPath)))) = $0
            else { return false }
            return parentPath == "/tmp/voyager"
        }
        await store.finish()
    }

    func testPasteCommandUsesCurrentNavigationPath() async {
        var initialState = FileManagerFeature.State()
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.request(.paste))
        await store.receive {
            guard case let .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(
                .pasteItems(destinationPath: destinationPath),
            ))))) = $0
            else { return false }
            return destinationPath == "/tmp/voyager"
        }
        await store.finish()
    }

    func testToggleSidebarCommandUsesCurrentSidebarState() async {
        var initialState = FileManagerFeature.State()
        initialState.sidebar.sidebarVisible = true

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.request(.toggleSidebar))
        await store.receive {
            guard case let .sidebar(.setSidebarVisible(visible)) = $0 else { return false }
            return visible == false
        }
        await store.finish()
    }

    func testToggleComposerCommandUsesCurrentComposerState() async {
        var initialState = FileManagerFeature.State()
        initialState.content.composer.isPresented = false

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }
        // Non-exhaustive: focus on the key delegate/state change; intermediate actions are noisy.
        store.exhaustivity = .off

        await store.send(.request(.toggleComposer))
        await store.receive {
            guard case let .content(.composer(.view(.setPresented(presented)))) = $0 else { return false }
            return presented == true
        }
        await store.finish()
    }
}

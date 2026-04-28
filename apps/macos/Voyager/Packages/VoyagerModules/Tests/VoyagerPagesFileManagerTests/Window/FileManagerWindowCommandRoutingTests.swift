import ComposableArchitecture
import XCTest

@testable import VoyagerPagesFileManager

@MainActor
final class FileManagerWindowCommandRoutingTests: XCTestCase {
    private func makeStore(path: String = "/tmp/test") -> TestStore<FileManagerWindowState, FileManagerWindowAction> {
        TestStore(
            initialState: FileManagerWindowState.makeInitial(path: path),
            reducer: { FileManagerWindowCommandRoutingReducer() },
        )
    }

    // MARK: - Navigation Commands

    func testGoBackRoutesToNavigationView() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.goBack))
        await store.receive {
            guard case .navigation(.view(.goBack)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testGoForwardRoutesToNavigationView() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.goForward))
        await store.receive {
            guard case .navigation(.view(.goForward)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testGoToEnclosingDirectoryRoutesToNavigationView() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.goToEnclosingDirectory))
        await store.receive {
            guard case .navigation(.view(.goToEnclosingDirectory)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - Entry Editing Commands

    func testCutRoutesToClipboard() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.cut))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.cutSelectedItems))))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    func testCopyRoutesToClipboard() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.copy))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedItems))))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    func testDuplicateRoutesToClipboard() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.duplicate))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.duplicateSelectedItems))))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    func testMakeAliasRoutesToMutation() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.makeAlias))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.mutation(.createAliasForSelectedItems))))) =
                $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - Entry Copying Commands

    func testCopyAbsolutePathsRoutesToClipboard() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.copyAbsolutePaths))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedAbsolutePaths))))) =
                $0
            else { return false }
            return true
        }
        await store.finish()
    }

    func testCopyURLsRoutesToClipboard() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.copyURLs))
        await store.receive {
            guard case .content(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedURLs))))) = $0
            else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - Selection Commands

    func testOpenSelectedItemWithEmptySelectionProducesNoEffect() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    func testQuickLookSelectedItemWithEmptySelectionProducesNoEffect() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    func testSelectAllRoutesToContent() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.selectAll))
        await store.receive {
            guard case .content(.view(.selectAllEntries)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - View Options

    func testToggleShowHiddenFilesRoutesToContent() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.toggleShowHiddenFiles))
        await store.receive {
            guard case .content(.view(.toggleShowHiddenFilesAndReload)) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - Composer Commands

    func testSaveCollectionRoutesToComposer() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.saveCollection))
        await store.receive {
            guard case let .content(.composer(.view(viewAction))) = $0 else { return false }
            guard case .saveCollection = viewAction else { return false }
            return true
        }
        await store.finish()
    }

    func testSaveCollectionAsRoutesToComposer() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.saveCollectionAs))
        await store.receive {
            guard case let .content(.composer(.view(viewAction))) = $0 else { return false }
            guard case .saveCollectionAs = viewAction else { return false }
            return true
        }
        await store.finish()
    }

    // MARK: - Undo/Redo

    func testUndoRoutesToEntryOperations() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.requestUndo))
        await store.receive {
            guard case .content(.entryViewLayout(.entryOperations(.undoRedo(.requestUndo)))) = $0 else { return false }
            return true
        }
        await store.finish()
    }

    func testRedoRoutesToEntryOperations() async {
        let store = makeStore()
        store.exhaustivity = .off
        await store.send(.request(.requestRedo))
        await store.receive {
            guard case .content(.entryViewLayout(.entryOperations(.undoRedo(.requestRedo)))) = $0 else { return false }
            return true
        }
        await store.finish()
    }
}

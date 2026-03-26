import ComposableArchitecture
@testable import Voyager
import XCTest

@MainActor
final class FileManagerWindowCommandRoutingTests: XCTestCase {
    func testOpenAndQuickLookCommandsWithSelectionRouteThroughSharedEntryCommandContract() async {
        let selected = makeEntry(name: "selected", fullPath: "/tmp/voyager/selected.txt")

        let cases: [(FileManagerWindowAction.WindowCommand, (EntryOperationsCommand) -> Bool)] = [
            (.openSelectedItem, { entryCommand in
                guard case .navigation(.openSelectedItem) = entryCommand else { return false }
                return true
            }),
            (.quickLookSelectedItem, { entryCommand in
                guard case .navigation(.quickLookSelectedItem) = entryCommand else { return false }
                return true
            }),
        ]

        for (command, matcher) in cases {
            var initialState = FileManagerFeature.State()
            initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.content.entryViewLayout.entries = [selected]
            initialState.content.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerFeature()
            }
            store.exhaustivity = .off

            await store.send(.request(command))
            await store.receive { action in
                guard case let .content(.entryViewLayout(.delegate(.executeCommand(entryCommand)))) = action else {
                    return false
                }
                return matcher(entryCommand)
            }
            await store.finish()
        }
    }

    func testEditAndCopyCommandsWithSelectionRouteThroughSharedEntryCommandContract() async {
        let selected = makeEntry(name: "selected", fullPath: "/tmp/voyager/selected.txt")

        let cases: [(FileManagerWindowAction.WindowCommand, (EntryOperationsCommand) -> Bool)] = [
            (.cut, {
                if case .clipboard(.cutSelectedItems) = $0 { return true }
                return false
            }),
            (.copy, {
                if case .clipboard(.copySelectedItems) = $0 { return true }
                return false
            }),
            (.duplicate, {
                if case .clipboard(.duplicateSelectedItems) = $0 { return true }
                return false
            }),
            (.copyAbsolutePaths, {
                if case .clipboard(.copySelectedAbsolutePaths) = $0 { return true }
                return false
            }),
            (.copyURLs, {
                if case .clipboard(.copySelectedURLs) = $0 { return true }
                return false
            }),
        ]

        for (command, matcher) in cases {
            var initialState = FileManagerFeature.State()
            initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.content.entryViewLayout.entries = [selected]
            initialState.content.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerFeature()
            }
            store.exhaustivity = .off

            await store.send(.request(command))
            await store.receive { action in
                guard case let .content(.entryViewLayout(.delegate(.executeCommand(entryCommand)))) = action else {
                    return false
                }
                return matcher(entryCommand)
            }
            await store.finish()
        }
    }

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
            guard case let .content(.entryViewLayout(.entryOperations(.edit(editAction)))) = $0,
                  case let .createNewFolder(payload) = editAction
            else { return false }
            return payload.parentPath == "/tmp/voyager"
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
            guard case let .sidebar(.view(.setSidebarVisible(visible))) = $0 else { return false }
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

    func testOpenSelectedItemCommandWithNoSelectionDoesNothing() async {
        var initialState = FileManagerFeature.State()
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.openSelectedItem))
        await store.finish()
    }

    func testQuickLookCommandWithNoSelectionDoesNothing() async {
        var initialState = FileManagerFeature.State()
        initialState.content.navigation.seedInitialFolderPath("/tmp/voyager")

        let store = TestStore(initialState: initialState) {
            FileManagerFeature()
        }

        await store.send(.request(.quickLookSelectedItem))
        await store.finish()
    }

    private func makeEntry(name: String, fullPath: String) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: false,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: "txt",
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

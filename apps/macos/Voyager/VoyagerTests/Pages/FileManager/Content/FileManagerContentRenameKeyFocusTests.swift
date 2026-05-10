import ComposableArchitecture
import Foundation
@testable import Voyager
import VoyagerEntitiesEntry
import VoyagerFeaturesEntryOperations
import VoyagerShared
import XCTest

/// Tests for key command focus restoration policy in list and grid modes.
///
/// These tests verify the reducer-level key command handling for the rename action.
/// View-level focus is not directly testable in XCTest, so we verify the key command
/// routing logic works correctly in both list and grid layouts.
@MainActor
final class FileManagerContentRenameKeyFocusTests: XCTestCase {
    // MARK: - Key Command Focus Restore Policy Tests

    /// Verifies that selection changes do not interfere with an active rename session.
    /// When renamingItemId is non-nil, the key command handler should not start a new rename.
    func testSelectionChangeDoesNotInterfereWithActiveRename() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            for keyCode in [36, 76] { // Return and Keypad Enter
                let selected = makeEntry(name: "selected.txt", fullPath: "/tmp/voyager/selected.txt")

                var initialState = FileManagerContentState()
                initialState.entryViewLayout.mode = layout
                initialState.navigation.seedInitialFolderPath("/tmp/voyager")
                initialState.entryViewLayout.entries = [selected]
                initialState.entryViewLayout.entryOperations.items = [selected]
                initialState.entryViewLayout.selectedIds = [selected.id]
                // Simulate an active rename session
                initialState.entryViewLayout.entryOperations.renamingItemId = selected.id

                let store = TestStore(initialState: initialState) {
                    FileManagerContentFeature()
                }

                // When pressing Return/Enter during an active rename, nothing should happen
                await store.send(.view(.handleKeyCommand(
                    KeyCommand(
                        keyCode: UInt16(keyCode),
                        modifiers: [],
                        characters: nil,
                        charactersIgnoringModifiers: nil,
                    ),
                )))
                await store.finish()
            }
        }
    }

    /// Verifies that Return and Keypad Enter key commands reach the rename path in list mode.
    /// This test confirms that the reducer-level handling works for list layout.
    func testListModeReturnAndKeypadEnterReachRenamePath() async {
        for keyCode in [36, 76] { // Return and Keypad Enter
            let selected = makeEntry(name: "document", fullPath: "/tmp/voyager/document.txt", fileExtension: "txt")

            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = .list
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.entryViewLayout.entries = [selected]
            initialState.entryViewLayout.entryOperations.items = [selected]
            initialState.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.handleKeyCommand(
                KeyCommand(keyCode: UInt16(keyCode), modifiers: [], characters: nil, charactersIgnoringModifiers: nil),
            )))

            await store.receive { action in
                guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else { return false }
                return item.id == selected.id && text == "document"
            }

            await store.finish()
        }
    }

    /// Verifies that Return and Keypad Enter key commands reach the rename path in grid mode.
    /// This test confirms the grid layout continues to work as before.
    func testGridModeReturnAndKeypadEnterReachRenamePath() async {
        for keyCode in [36, 76] { // Return and Keypad Enter
            let selected = makeEntry(
                name: "spreadsheet",
                fullPath: "/tmp/voyager/spreadsheet.xlsx",
                fileExtension: "xlsx",
            )

            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = .grid
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.entryViewLayout.entries = [selected]
            initialState.entryViewLayout.entryOperations.items = [selected]
            initialState.entryViewLayout.selectedIds = [selected.id]

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.handleKeyCommand(
                KeyCommand(keyCode: UInt16(keyCode), modifiers: [], characters: nil, charactersIgnoringModifiers: nil),
            )))

            await store.receive { action in
                guard case let .entryViewLayout(.delegate(.startRename(item, text))) = action else { return false }
                return item.id == selected.id && text == "spreadsheet"
            }

            await store.finish()
        }
    }

    /// Verifies that layout change during an active rename cancels the rename.
    /// This ensures the focus policy doesn't leave stale rename state.
    func testLayoutChangeDuringActiveRenameCancelsRename() async {
        let selected = makeEntry(name: "file.txt", fullPath: "/tmp/voyager/file.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = .list
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [selected]
        initialState.entryViewLayout.entryOperations.items = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]
        initialState.entryViewLayout.entryOperations.renamingItemId = selected.id

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.changeLayout(.grid)))

        // The layout change should cancel the active rename
        await store.receive { action in
            guard case .entryViewLayout(.entryOperations(.edit(.cancelRename))) = action else { return false }
            return true
        }

        await store.finish()
    }

    // MARK: - Helper Methods

    private func makeEntry(
        name: String,
        fullPath: String,
        isFolder: Bool = false,
        fileExtension: String? = nil,
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ext = fileExtension ?? (name.components(separatedBy: ".").last ?? "")
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: ext,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Document",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

import ComposableArchitecture
import Foundation
@testable import Voyager
import XCTest

@MainActor
final class FileManagerContentKeyCommandHandlerTests: XCTestCase {
    func testOpenAndQuickLookShortcutsUseSharedCommandContextInListAndGrid() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 125, modifiers: [.command], characters: nil, charactersIgnoringModifiers: nil),
                commandMatches: {
                    guard case .navigation(.openSelectedItem) = $0 else { return false }
                    return true
                },
            )

            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 49, modifiers: [], characters: " ", charactersIgnoringModifiers: " "),
                commandMatches: {
                    guard case .navigation(.quickLookSelectedItem) = $0 else { return false }
                    return true
                },
            )
        }
    }

    func testEditShortcutsUseSharedCommandContextInListAndGrid() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 7, modifiers: [.command], characters: "x", charactersIgnoringModifiers: "x"),
                commandMatches: {
                    guard case .clipboard(.cutSelectedItems) = $0 else { return false }
                    return true
                },
            )

            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 8, modifiers: [.command], characters: "c", charactersIgnoringModifiers: "c"),
                commandMatches: {
                    guard case .clipboard(.copySelectedItems) = $0 else { return false }
                    return true
                },
            )

            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 9, modifiers: [.command], characters: "v", charactersIgnoringModifiers: "v"),
                commandMatches: {
                    guard case let .clipboard(.pasteItems(destinationPath)) = $0 else { return false }
                    return destinationPath == "/tmp/voyager"
                },
            )

            await assertShortcutRoutesThroughSharedCommandContext(
                layout: layout,
                shortcut: .init(keyCode: 2, modifiers: [.command], characters: "d", charactersIgnoringModifiers: "d"),
                commandMatches: {
                    guard case .clipboard(.duplicateSelectedItems) = $0 else { return false }
                    return true
                },
            )
        }
    }

    func testToggleHiddenFilesShortcutHasListAndGridParity() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = layout
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")
            initialState.entryViewLayout.showHiddenFiles = false

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }
            store.exhaustivity = .off

            await store.send(.view(.handleKeyCommand(
                .init(keyCode: 47, modifiers: [.command, .shift], characters: ".", charactersIgnoringModifiers: "."),
            )))
            await store.receive { action in
                guard case .view(.toggleShowHiddenFilesAndReload) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case .entryViewLayout(.view(.toggleShowHiddenFiles)) = action else { return false }
                return true
            }
            await store.receive { action in
                guard case let .entryViewLayout(.entryOperations(.loading(.loadItems(
                    path: path,
                    showHidden: showHidden,
                )))) =
                    action
                else { return false }
                return path == "/tmp/voyager" && showHidden
            }
            await store.finish()
        }
    }

    func testOpenAndQuickLookShortcutsWithNoSelectionDoNothingInListAndGrid() async {
        for layout in [EntryViewLayoutState.Mode.list, .grid] {
            var initialState = FileManagerContentState()
            initialState.entryViewLayout.mode = layout
            initialState.navigation.seedInitialFolderPath("/tmp/voyager")

            let store = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }

            await store.send(.view(.handleKeyCommand(
                .init(keyCode: 125, modifiers: [.command], characters: nil, charactersIgnoringModifiers: nil),
            )))
            await store.finish()

            let quickLookStore = TestStore(initialState: initialState) {
                FileManagerContentFeature()
            }

            await quickLookStore.send(.view(.handleKeyCommand(
                .init(keyCode: 49, modifiers: [], characters: " ", charactersIgnoringModifiers: " "),
            )))
            await quickLookStore.finish()
        }
    }

    func testOpenSelectedItemRoutesVoycollPackageToCollectionNavigation() async {
        let selected = makeEntry(
            name: "Sample.voycoll",
            fullPath: "/tmp/voyager/Sample.voycoll",
            isFolder: true,
            fileExtension: "voycoll",
        )

        var initialState = FileManagerContentState()
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem)))))
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(
                command: command,
                context: context,
            )))) =
                action
            else { return false }
            guard case .navigation(.openSelectedItem) = command else { return false }
            return context.selectedIds == Set([selected.id])
                && context.displayItems == [selected]
                && context.currentPath == "/tmp/voyager"
        }
        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.delegate(.openCollectionFile(url)))) = action else {
                return false
            }
            return url.path == "/tmp/voyager/Sample.voycoll"
        }
        await store.receive { action in
            guard case let .internal(.requestNavigation(.view(.openCollectionFile(url)))) = action else {
                return false
            }
            return url.path == "/tmp/voyager/Sample.voycoll"
        }
        await store.finish()
    }

    private func assertShortcutRoutesThroughSharedCommandContext(
        layout: EntryViewLayoutState.Mode,
        shortcut: KeyCommand,
        commandMatches: @escaping (EntryOperationsCommand) -> Bool,
    ) async {
        let selected = makeEntry(name: "selected", fullPath: "/tmp/voyager/selected.txt")

        var initialState = FileManagerContentState()
        initialState.entryViewLayout.mode = layout
        initialState.navigation.seedInitialFolderPath("/tmp/voyager")
        initialState.entryViewLayout.entries = [selected]
        initialState.entryViewLayout.selectedIds = [selected.id]

        let store = TestStore(initialState: initialState) {
            FileManagerContentFeature()
        }
        store.exhaustivity = .off

        await store.send(.view(.handleKeyCommand(shortcut)))

        await store.receive { action in
            guard case let .entryViewLayout(.delegate(.executeCommand(command))) = action else { return false }
            return commandMatches(command)
        }

        await store.receive { action in
            guard case let .entryViewLayout(.entryOperations(.routing(.executeCommand(
                command: command,
                context: context,
            )))) =
                action
            else { return false }
            return commandMatches(command)
                && context.selectedIds == Set([selected.id])
                && context.displayItems == [selected]
                && context.currentPath == "/tmp/voyager"
        }

        await store.finish()
    }

    private func makeEntry(
        name: String,
        fullPath: String,
        isFolder: Bool = false,
        fileExtension: String = "txt",
    ) -> EntryModel {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EntryModel(
            name: name,
            fullPath: fullPath,
            isFolder: isFolder,
            isHidden: false,
            size: 1,
            modifiedDate: date,
            fileExtension: fileExtension,
            facets: EntryFacets(
                createdDate: date,
                addedDate: date,
                lastOpenedDate: nil,
                kind: isFolder ? "Folder" : "Text",
                creatorApplication: nil,
                tags: nil,
                supplementaryMetadata: nil,
            ),
        )
    }
}

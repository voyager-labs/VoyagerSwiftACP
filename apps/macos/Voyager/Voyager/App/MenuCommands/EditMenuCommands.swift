import AppKit
import ComposableArchitecture
import SwiftUI

struct EditMenuCommands: Commands {
    @FocusedValue(\.fileManagerStore)
    var fileManagerStore: StoreOf<FileManagerFeature>?

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                fileManagerStore?.send(.fsItems(.cutSelectedItems))
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(fileManagerStore?.fsItems.selectedIds.isEmpty ?? true)

            Button("Copy") {
                fileManagerStore?.send(.fsItems(.copySelectedItems))
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(fileManagerStore?.fsItems.selectedIds.isEmpty ?? true)

            Button("Paste") {
                if let currentPath = fileManagerStore?.currentPath {
                    fileManagerStore?.send(.fsItems(.pasteItems(destinationPath: currentPath)))
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(fileManagerStore?.fsItems.clipboardItems.isEmpty ?? true)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                fileManagerStore?.send(.fsItems(.selectAll))
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(fileManagerStore == nil)
        }
    }
}

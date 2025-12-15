import AppKit
import ComposableArchitecture
import SwiftUI

struct EditMenuCommands: Commands {
    @ObservedObject private var appDelegate: AppDelegate

    init() {
        guard let shared = AppDelegate.shared else {
            fatalError("AppDelegate.shared must be initialized before EditMenuCommands")
        }
        appDelegate = shared
    }

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                appDelegate.currentFileManagerStore?.send(.fsItems(.cutSelectedItems))
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!appDelegate.hasSelectedItems)

            Button("Copy") {
                appDelegate.currentFileManagerStore?.send(.fsItems(.copySelectedItems))
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!appDelegate.hasSelectedItems)

            Button("Paste") {
                if let currentPath = appDelegate.currentFileManagerStore?.currentPath {
                    appDelegate.currentFileManagerStore?
                        .send(.fsItems(.pasteItems(destinationPath: currentPath)))
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!appDelegate.hasClipboardItems)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                appDelegate.currentFileManagerStore?.send(.fsItems(.selectAll))
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!appDelegate.hasStore)
        }
    }
}

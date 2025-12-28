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

    private func firstResponderCanHandle(_ selector: Selector) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSResponder else { return false }
        return responder.responds(to: selector)
    }

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.fsItems(.cutSelectedItems))
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(false)

            Button("Copy") {
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.fsItems(.copySelectedItems))
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(false)

            Button("Paste") {
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                } else if let currentPath = appDelegate.currentFileManagerStore?.currentPath {
                    appDelegate.currentFileManagerStore?.send(.fsItems(.pasteItems(destinationPath: currentPath)))
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(false)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.fsItems(.selectAll))
                }
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(false)
        }
    }
}

import AppKit
import ComposableArchitecture
import SwiftUI

struct EditMenuCommands: Commands {
    @ObservedObject private var appDelegate: AppDelegate
    private let undoSelector = Selector(("undo:"))
    private let redoSelector = Selector(("redo:"))

    init() {
        guard let shared = AppDelegate.shared else {
            fatalError("AppDelegate.shared must be initialized before EditMenuCommands")
        }
        appDelegate = shared
    }

    private func isTextEditingResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func textResponderUndoManager() -> UndoManager? {
        (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager
    }

    private func canUndoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return textResponderUndoManager()?.canUndo == true
    }

    private func canRedoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return textResponderUndoManager()?.canRedo == true
    }

    var body: some Commands {
        let canUndoResponder = canUndoInTextResponder()
        let canRedoResponder = canRedoInTextResponder()
        let canUndo = canUndoResponder || appDelegate.canUndo
        let canRedo = canRedoResponder || appDelegate.canRedo

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if canUndoInTextResponder(),
                   NSApp.sendAction(undoSelector, to: nil, from: nil)
                {
                    return
                }
                appDelegate.currentFileManagerStore?.send(.entries(.requestUndo))
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canUndo)

            Button("Redo") {
                if canRedoInTextResponder(),
                   NSApp.sendAction(redoSelector, to: nil, from: nil)
                {
                    return
                }
                appDelegate.currentFileManagerStore?.send(.entries(.requestRedo))
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!canRedo)
        }

        CommandGroup(after: .undoRedo) {
            let isComposerPresented = appDelegate.currentFileManagerStore?.composer.isPresented == true
            let composerTitle = isComposerPresented
                ? "Close Collection Filter Composer"
                : "Open Collection Filter Composer"
            Button(composerTitle) {
                guard let store = appDelegate.currentFileManagerStore else { return }
                if store.composer.isPresented {
                    store.send(.exitComposer)
                } else {
                    store.send(.enterComposer)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(appDelegate.currentFileManagerStore == nil)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.entries(.cutSelectedItems))
                }
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(false)

            Button("Copy") {
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.entries(.copySelectedItems))
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(false)

            Button("Paste") {
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                } else if let currentPath = appDelegate.currentFileManagerStore?.currentPath {
                    appDelegate.currentFileManagerStore?.send(.entries(.pasteItems(destinationPath: currentPath)))
                }
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(false)

            Button("Duplicate") {
                appDelegate.currentFileManagerStore?.send(.entries(.duplicateSelectedItems))
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(appDelegate.currentFileManagerStore?.entries.selectedIds.isEmpty ?? true)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) {
                } else {
                    appDelegate.currentFileManagerStore?.send(.entries(.selectAll))
                }
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(false)
        }
    }
}

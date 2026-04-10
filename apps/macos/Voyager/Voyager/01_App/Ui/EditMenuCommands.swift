import AppKit
import ComposableArchitecture
import SwiftUI

@ViewAction(for: MenuCommandsFeature.self)
struct EditMenuCommands: Commands {
    private let undoSelector = Selector(("undo:"))
    private let redoSelector = Selector(("redo:"))

    let store: StoreOf<MenuCommandsFeature>

    @ObservedObject private var viewStore: ViewStore<MenuCommandsState, MenuCommandsAction>

    init(appRootStore: StoreOf<AppRootFeature>) {
        let menuStore = appRootStore.scope(state: \.menuCommands, action: \.menuCommands)
        store = menuStore
        viewStore = ViewStore(
            menuStore,
            observe: { $0 },
        )
    }

    var body: some Commands {
        let canUndoResponder = canUndoInTextResponder()
        let canRedoResponder = canRedoInTextResponder()
        let canUndo = canUndoResponder || viewStore.canUndo
        let canRedo = canRedoResponder || viewStore.canRedo

        let selectedCount = viewStore.selectedItemCount
        let hasSelectedItems = selectedCount > 0
        let copyAbsolutePathTitle = selectedCount == 1 ? "Copy Absolute Path" : "Copy Absolute Paths"
        let copyURLTitle = selectedCount == 1 ? "Copy URL" : "Copy URLs"

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                sendUndoRedoAction(
                    canHandleByTextResponder: canUndoInTextResponder(),
                    selector: undoSelector,
                    fallback: .requestUndo,
                )
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canUndo)

            Button("Redo") {
                sendUndoRedoAction(
                    canHandleByTextResponder: canRedoInTextResponder(),
                    selector: redoSelector,
                    fallback: .requestRedo,
                )
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!canRedo)
        }

        CommandGroup(after: .undoRedo) {
            let isComposerPresented = viewStore.isComposerPresented
            let composerTitle = isComposerPresented
                ? "Close Collection Filter Composer"
                : "Open Collection Filter Composer"
            Button(composerTitle) {
                sendEditCommand(.toggleComposer)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!viewStore.hasFocusedWindow)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                sendTextResponderAction(#selector(NSText.cut(_:)), fallback: .cut)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                sendTextResponderAction(#selector(NSText.copy(_:)), fallback: .copy)
            }
            .keyboardShortcut("c", modifiers: .command)

            Divider()

            Button(copyAbsolutePathTitle) {
                sendEditCommand(.copyAbsolutePaths)
            }
            .disabled(!hasSelectedItems)

            Button(copyURLTitle) {
                sendEditCommand(.copyURLs)
            }
            .disabled(!hasSelectedItems)

            Button("Paste") {
                sendTextResponderAction(#selector(NSText.paste(_:)), fallback: .paste)
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Duplicate") {
                sendEditCommand(.duplicate)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasSelectedItems)

            Button("Make Alias") {
                sendEditCommand(.makeAlias)
            }
            .disabled(!hasSelectedItems)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                sendTextResponderAction(#selector(NSText.selectAll(_:)), fallback: .selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
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

    private func sendEditCommand(_ command: MenuCommandItem.EditCommand) {
        send(.edit(command))
    }

    private func sendTextResponderAction(_ selector: Selector, fallback command: MenuCommandItem.EditCommand) {
        guard !NSApp.sendAction(selector, to: nil, from: nil) else { return }
        sendEditCommand(command)
    }

    private func sendUndoRedoAction(
        canHandleByTextResponder: Bool,
        selector: Selector,
        fallback command: MenuCommandItem.EditCommand,
    ) {
        if canHandleByTextResponder,
           NSApp.sendAction(selector, to: nil, from: nil)
        {
            return
        }

        sendEditCommand(command)
    }
}

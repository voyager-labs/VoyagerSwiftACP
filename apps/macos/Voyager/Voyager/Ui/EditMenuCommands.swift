import AppKit
import ComposableArchitecture
import SwiftUI

enum EditMenuUndoRedoRouting: Equatable {
    case native
    case window

    static func resolve(
        canHandleByTextResponder: Bool,
        sendNativeAction: () -> Bool,
    ) -> Self {
        guard canHandleByTextResponder, sendNativeAction() else { return .window }
        return .native
    }
}

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
        let canPerformEntryCommands = viewStore.canPerformEntryCommands
        let canCut = Self.canPerformTextOrEntryCommand(
            canHandleByTextResponder: canTextResponderHandle(#selector(NSText.cut(_:))),
            canPerformEntryCommands: canPerformEntryCommands,
        )
        let canCopy = Self.canPerformTextOrEntryCommand(
            canHandleByTextResponder: canTextResponderHandle(#selector(NSText.copy(_:))),
            canPerformEntryCommands: canPerformEntryCommands,
        )
        let canPaste = Self.canPerformTextOrEntryCommand(
            canHandleByTextResponder: canTextResponderHandle(#selector(NSText.paste(_:))),
            canPerformEntryCommands: canPerformEntryCommands,
        )
        let canSelectAll = Self.canPerformTextOrEntryCommand(
            canHandleByTextResponder: canTextResponderHandle(#selector(NSText.selectAll(_:))),
            canPerformEntryCommands: canPerformEntryCommands,
        )
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

            let contextualAiChatTitle = viewStore.isContextualAiChatPresented
                ? "Close Contextual AI Chat"
                : "Open Contextual AI Chat"
            Button(contextualAiChatTitle) {
                sendEditCommand(.openContextualAiChat)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!viewStore.hasFocusedWindow)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                sendTextResponderAction(#selector(NSText.cut(_:)), fallback: .cut)
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!canCut)

            Button("Copy") {
                sendTextResponderAction(#selector(NSText.copy(_:)), fallback: .copy)
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!canCopy)

            Divider()

            Button(copyAbsolutePathTitle) {
                sendEditCommand(.copyAbsolutePaths)
            }
            .disabled(!canPerformEntryCommands || !hasSelectedItems)

            Button(copyURLTitle) {
                sendEditCommand(.copyURLs)
            }
            .disabled(!canPerformEntryCommands || !hasSelectedItems)

            Button("Paste") {
                sendTextResponderAction(#selector(NSText.paste(_:)), fallback: .paste)
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!canPaste)

            Button("Duplicate") {
                sendEditCommand(.duplicate)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!canPerformEntryCommands || !hasSelectedItems)

            Button("Make Alias") {
                sendEditCommand(.makeAlias)
            }
            .disabled(!canPerformEntryCommands || !hasSelectedItems)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Select All") {
                sendTextResponderAction(#selector(NSText.selectAll(_:)), fallback: .selectAll)
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!canSelectAll)
        }
    }

    static func canPerformTextOrEntryCommand(
        canHandleByTextResponder: Bool,
        canPerformEntryCommands: Bool,
    ) -> Bool {
        canHandleByTextResponder || canPerformEntryCommands
    }

    private func isTextEditingResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func canTextResponderHandle(_ selector: Selector) -> Bool {
        isTextEditingResponder() && NSApp.target(forAction: selector, to: nil, from: nil) != nil
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
        let routing = EditMenuUndoRedoRouting.resolve(
            canHandleByTextResponder: canHandleByTextResponder,
            sendNativeAction: { NSApp.sendAction(selector, to: nil, from: nil) },
        )
        guard routing == .window else { return }
        sendEditCommand(command)
    }
}

import AppKit
import ComposableArchitecture

enum FileManagerContentKeyCommandHandler {
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    static func effect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if command.keyCode == 53, state.entries.isRenaming {
            return .send(.entries(.cancelRename))
        }

        if command.keyCode == 36,
           command.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
        {
            if state.entries.isRenaming {
                return .send(.entries(.commitRename))
            }

            if state.entries.selectedIds.count == 1,
               let selectedId = state.entries.selectedIds.first
            {
                return .send(.entries(.startRename(id: selectedId)))
            }

            return .none
        }

        if command.keyCode == 49,
           command.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
        {
            if state.canQuickLookSelectedItem {
                return .send(.entries(.quickLookSelectedItem))
            }
            return .none
        }

        if command.keyCode == 51,
           command.modifiers.contains(.command)
        {
            if state.entries.selectedIds.isEmpty {
                return .none
            }

            if command.modifiers.contains(.option) {
                return .send(.entries(.deleteSelectedItemsImmediately))
            }
            return .send(.entries(.moveSelectedItemsToTrash))
        }

        if let movementEffect = selectionMovementEffect(for: command, state: state) {
            return movementEffect
        }

        if command.modifiers.contains(.command) {
            if command.modifiers.isDisjoint(with: [.option, .control]),
               command.charactersIgnoringModifiers == "z"
            {
                if state.composer.isPresented {
                    return .none
                }

                if command.modifiers.contains(.shift) {
                    if canRedoInTextResponder(),
                       NSApp.sendAction(Self.redoSelector, to: nil, from: nil)
                    {
                        return .none
                    }
                    return .send(.entryOperations(.requestRedo))
                }

                if canUndoInTextResponder(),
                   NSApp.sendAction(Self.undoSelector, to: nil, from: nil)
                {
                    return .none
                }
                return .send(.entryOperations(.requestUndo))
            }

            if command.characters == ".",
               command.modifiers.contains(.shift)
            {
                return .send(.entries(.toggleShowHiddenFiles))
            }
        }

        return .none
    }

    private static func selectionMovementEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }

        let isShiftPressed = command.modifiers.contains(.shift)

        switch command.keyCode {
        case 123 where state.viewLayout == .grid:
            return .send(.entries(.selectPreviousItem(isShiftPressed: isShiftPressed)))
        case 124 where state.viewLayout == .grid:
            return .send(.entries(.selectNextItem(isShiftPressed: isShiftPressed)))
        case 126 where state.viewLayout == .grid:
            return .send(.entries(.selectByOffset(
                offset: -state.entries.gridColumnCount,
                isShiftPressed: isShiftPressed,
            )))
        case 125 where state.viewLayout == .grid:
            return .send(.entries(.selectByOffset(
                offset: state.entries.gridColumnCount,
                isShiftPressed: isShiftPressed,
            )))
        case 126:
            return .send(.entries(.selectPreviousItem(isShiftPressed: isShiftPressed)))
        case 125:
            return .send(.entries(.selectNextItem(isShiftPressed: isShiftPressed)))
        default:
            return nil
        }
    }

    private static func isTextEditingResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private static func canUndoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager?.canUndo == true
    }

    private static func canRedoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager?.canRedo == true
    }
}

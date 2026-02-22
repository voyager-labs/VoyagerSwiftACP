import AppKit
import ComposableArchitecture

enum FileManagerContentKeyCommandHandler {
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    static func effect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if let effect = renameKeyEffect(for: command, state: state) { return effect }
        if let effect = quickLookKeyEffect(for: command, state: state) { return effect }
        if let effect = deleteKeyEffect(for: command, state: state) { return effect }
        if let movementEffect = selectionMovementEffect(for: command, state: state) { return movementEffect }
        if let effect = commandModifierEffect(for: command, state: state) { return effect }
        return .none
    }

    private static func renameKeyEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        if command.keyCode == 53, state.entryViewLayout.isRenaming {
            return .send(.entryViewLayout(.cancelRename))
        }

        guard command.keyCode == 36,
              command.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
        else {
            return nil
        }

        if state.entryViewLayout.isRenaming {
            return .send(.entries(.commitRename))
        }

        if state.entryViewLayout.selectedIds.count == 1,
           let selectedId = state.entryViewLayout.selectedIds.first
        {
            return .send(.entries(.startRename(id: selectedId)))
        }

        return .none
    }

    private static func quickLookKeyEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.keyCode == 49,
              command.modifiers.isDisjoint(with: [.command, .option, .control, .shift])
        else {
            return nil
        }

        let selectedIds = state.entryViewLayout.selectedIds
        let selectedEntries = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
        if selectedEntries.count == 1, let file = selectedEntries.first {
            return .send(.entryOperations(.quickLookFile(file: file)))
        }
        if !selectedEntries.isEmpty {
            return .send(.entryOperations(.quickLookFiles(files: selectedEntries)))
        }
        return .none
    }

    private static func deleteKeyEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.keyCode == 51,
              command.modifiers.contains(.command)
        else {
            return nil
        }

        let selectedIds = state.entryViewLayout.selectedIds
        let selectedEntries = Array(state.entryOperations.displayItems.filter { selectedIds.contains($0.id) })
        guard !selectedEntries.isEmpty else { return .none }

        if command.modifiers.contains(.option) {
            return .send(.entryOperations(.deleteImmediately(items: selectedEntries)))
        }
        return .send(.entryOperations(.moveToTrash(items: selectedEntries)))
    }

    private static func commandModifierEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.contains(.command) else { return nil }

        if command.modifiers.isDisjoint(with: [.option, .control]),
           command.charactersIgnoringModifiers == "z"
        {
            return undoRedoEffect(for: command, state: state)
        }

        if command.characters == ".", command.modifiers.contains(.shift) {
            return .send(.entries(.toggleShowHiddenFiles))
        }

        return nil
    }

    private static func undoRedoEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if state.composer.isPresented {
            return .none
        }

        if command.modifiers.contains(.shift) {
            if canRedoInTextResponder(), NSApp.sendAction(redoSelector, to: nil, from: nil) {
                return .none
            }
            return .send(.entryOperations(.requestRedo))
        }

        if canUndoInTextResponder(), NSApp.sendAction(undoSelector, to: nil, from: nil) {
            return .none
        }
        return .send(.entryOperations(.requestUndo))
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
                offset: -state.entryViewLayout.gridColumnCount,
                isShiftPressed: isShiftPressed,
            )))
        case 125 where state.viewLayout == .grid:
            return .send(.entries(.selectByOffset(
                offset: state.entryViewLayout.gridColumnCount,
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

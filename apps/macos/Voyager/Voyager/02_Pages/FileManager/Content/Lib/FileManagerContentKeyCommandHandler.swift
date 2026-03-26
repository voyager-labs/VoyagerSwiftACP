import AppKit
import ComposableArchitecture
import Foundation

enum FileManagerContentKeyCommandHandler {
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    static func effect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        if let effect = quickLookKeyEffect(for: command, state: state) { return effect }
        if let effect = deleteKeyEffect(for: command, state: state) { return effect }
        if let effect = renameKeyEffect(for: command, state: state) { return effect }
        if let movementEffect = selectionMovementEffect(for: command, state: state) { return movementEffect }
        if let effect = commandModifierEffect(for: command, state: state) { return effect }
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

        guard !state.entryViewLayout.selectedIds.isEmpty else { return .none }

        return .send(.entryViewLayout(.delegate(.executeCommand(.navigation(.quickLookSelectedItem)))))
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
        let selectedEntries = state.entryViewLayout.entries.filter { selectedIds.contains($0.id) }
        guard !selectedEntries.isEmpty else { return .none }
        let selectedPaths = selectedEntries.map(\.fullPath)

        if command.modifiers.contains(.option) {
            return .send(.entryViewLayout(.entryOperations(.trash(
                EntryOperationsAction.Trash.deleteImmediately(paths: selectedPaths),
            ))))
        }
        return .send(.entryViewLayout(.entryOperations(.trash(
            EntryOperationsAction.Trash.moveToTrash(paths: selectedPaths),
        ))))
    }

    private static func renameKeyEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.isDisjoint(with: [.command, .option, .control, .shift]),
              command.keyCode == 36 || command.keyCode == 76,
              state.entryViewLayout.entryOperations.renamingItemId == nil
        else {
            return nil
        }

        let selectedIds = state.entryViewLayout.selectedIds
        let selectedEntries = state.entryViewLayout.entries.filter { selectedIds.contains($0.id) }
        guard selectedEntries.count == 1, let entry = selectedEntries.first else { return .none }

        return .send(.entryViewLayout(.delegate(.startRename(id: entry.id, text: entry.name))))
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
            return .send(.view(.toggleShowHiddenFilesAndReload))
        }

        if let effect = entryCommandModifierEffect(for: command, state: state) {
            return effect
        }

        return nil
    }

    private static func entryCommandModifierEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        if command.keyCode == 125,
           command.modifiers.isDisjoint(with: [.option, .control, .shift])
        {
            guard !state.entryViewLayout.selectedIds.isEmpty else { return .none }
            return .send(.entryViewLayout(.delegate(.executeCommand(.navigation(.openSelectedItem)))))
        }

        guard command.modifiers.isDisjoint(with: [.option, .control, .shift]),
              let key = command.charactersIgnoringModifiers
        else {
            return nil
        }

        switch key {
        case "x":
            return .send(.entryViewLayout(.delegate(.executeCommand(.clipboard(.cutSelectedItems)))))

        case "c":
            return .send(.entryViewLayout(.delegate(.executeCommand(.clipboard(.copySelectedItems)))))

        case "v":
            return .send(.entryViewLayout(.delegate(.executeCommand(.clipboard(
                .pasteItems(destinationPath: state.navigation.currentPath),
            )))))

        case "d":
            return .send(.entryViewLayout(.delegate(.executeCommand(.clipboard(.duplicateSelectedItems)))))

        default:
            return nil
        }
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
            return .send(.entryViewLayout(.entryOperations(.undoRedo(
                EntryOperationsAction.UndoRedo.requestRedo,
            ))))
        }

        if canUndoInTextResponder(), NSApp.sendAction(undoSelector, to: nil, from: nil) {
            return .none
        }
        return .send(.entryViewLayout(.entryOperations(.undoRedo(
            EntryOperationsAction.UndoRedo.requestUndo,
        ))))
    }

    private static func selectionMovementEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }

        let isShiftPressed = command.modifiers.contains(.shift)

        switch command.keyCode {
        case 123 where state.entryViewLayout.mode == .grid:
            return selectionOffsetEffect(offset: -1, isShiftPressed: isShiftPressed, state: state)
        case 124 where state.entryViewLayout.mode == .grid:
            return selectionOffsetEffect(offset: 1, isShiftPressed: isShiftPressed, state: state)
        case 126 where state.entryViewLayout.mode == .grid:
            return selectionOffsetEffect(
                offset: -state.entryViewLayout.gridColumnCount,
                isShiftPressed: isShiftPressed,
                state: state,
            )
        case 125 where state.entryViewLayout.mode == .grid:
            return selectionOffsetEffect(
                offset: state.entryViewLayout.gridColumnCount,
                isShiftPressed: isShiftPressed,
                state: state,
            )
        case 126:
            return selectionOffsetEffect(offset: -1, isShiftPressed: isShiftPressed, state: state)
        case 125:
            return selectionOffsetEffect(offset: 1, isShiftPressed: isShiftPressed, state: state)
        default:
            return nil
        }
    }

    private static func selectionOffsetEffect(
        offset: Int,
        isShiftPressed: Bool,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.internal(.applySelectionOffset(
            offset: offset,
            isShiftPressed: isShiftPressed,
            orderedItemIds: state.entryViewLayout.entries.map(\.id),
        ))))
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

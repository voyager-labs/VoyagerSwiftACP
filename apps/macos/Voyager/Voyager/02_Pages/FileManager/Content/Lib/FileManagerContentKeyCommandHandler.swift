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

        let selectedEntries = state.selectedEntries
        guard !selectedEntries.isEmpty else { return nil }
        return .send(.entryViewLayout(.entryOperations(.quickLookFiles(paths: selectedEntries.map(\.fullPath)))))
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

        let selectedEntries = state.selectedEntries
        guard !selectedEntries.isEmpty else { return .none }
        let selectedPaths = selectedEntries.map(\.fullPath)

        if command.modifiers.contains(.option) {
            return .send(.entryViewLayout(.entryOperations(.deleteImmediately(paths: selectedPaths))))
        }
        return .send(.entryViewLayout(.entryOperations(.moveToTrash(paths: selectedPaths))))
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
            let show = !state.entryViewLayout.showHiddenFiles
            return .concatenate(
                .send(.entryViewLayout(.internal(.setShowHiddenFiles(show)))),
                reloadEntryItemsEffect(state: state, showHidden: show),
            )
        }

        return nil
    }

    private static func undoRedoEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        // Composer(FocusedTextField 포함)가 열려있으면 자체 undo/redo 처리
        // FocusedTextField는 NSTextField 기반으로 독립적으로 first responder 상태를 관리하며,
        // KeyCommandHostingView의 포커스 시스템을 우회함
        if state.composer.isPresented {
            return .none
        }

        // 텍스트 리스폰더 체인을 먼저 시도 (FocusedTextField 또는 다른 텍스트 필드용)
        // 사이드바/탭의 인라인 텍스트 편집이 자체 undo/redo를 처리할 수 있게 함
        if command.modifiers.contains(.shift) {
            if canRedoInTextResponder(), NSApp.sendAction(redoSelector, to: nil, from: nil) {
                return .none
            }
            return .send(.entryViewLayout(.entryOperations(.requestRedo)))
        }

        if canUndoInTextResponder(), NSApp.sendAction(undoSelector, to: nil, from: nil) {
            return .none
        }
        return .send(.entryViewLayout(.entryOperations(.requestUndo)))
    }

    private static func selectionMovementEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }

        let isShiftPressed = command.modifiers.contains(.shift)

        switch command.keyCode {
        case 123 where state.viewLayout == .grid:
            return selectionOffsetEffect(offset: -1, isShiftPressed: isShiftPressed, state: state)
        case 124 where state.viewLayout == .grid:
            return selectionOffsetEffect(offset: 1, isShiftPressed: isShiftPressed, state: state)
        case 126 where state.viewLayout == .grid:
            return selectionOffsetEffect(
                offset: -state.entryViewLayout.gridColumnCount,
                isShiftPressed: isShiftPressed,
                state: state,
            )
        case 125 where state.viewLayout == .grid:
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

    private static func reloadEntryItemsEffect(
        state: FileManagerContentState,
        showHidden: Bool,
    ) -> Effect<FileManagerContentAction> {
        switch state.navigation.navigationState {
        case let .folder(path):
            .send(.entryViewLayout(.entryOperations(.loadItems(path: path, showHidden: showHidden))))
        case .recents:
            .send(.entryViewLayout(.entryOperations(.loadRecentItems(showHidden: showHidden))))
        case let .tags(tagName):
            .send(.entryViewLayout(.entryOperations(.loadTagItems(tagName: tagName, showHidden: showHidden))))
        case .computer:
            .send(.entryViewLayout(.entryOperations(.loadComputerItems)))
        case .collection:
            .none
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

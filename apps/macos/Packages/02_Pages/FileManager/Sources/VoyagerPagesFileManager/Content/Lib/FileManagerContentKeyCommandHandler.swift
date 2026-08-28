import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesCollection
import VoyagerEntitiesEntry
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

enum FileManagerKeyCommandCompositionPolicy: Equatable {
    case preserveMarkedText
    case cancelMarkedText
}

enum FileManagerContentKeyCommandHandler {
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    /// 커밋된 타자 입력을 type-scroll 타깃으로 라우팅한다.
    /// 입력이 유효한 단일 문자이고 rename이 진행 중이 아니면, 표시 순서상 첫 매칭 엔트리로
    /// target을 교체한다. 매칭이 없으면 이전 pending target을 reset한다.
    static func typeScrollEffect(
        for text: String,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        // 방어 계층: 매처가 다시 검증하지만 여기서도 단일 문자 커밋을 보장한다.
        guard CommittedTypeScrollInput.character(from: text) != nil else { return .none }
        // rename이 우선권을 가지므로 rename 중에는 type-scroll을 비활성화한다.
        guard state.entryViewLayout.entryOperations.renamingItemId == nil else { return .none }

        let entries = typeScrollCandidateEntries(state: state)
        guard let firstMatch = EntryViewLayoutTypeScrollMatcher.firstMatchID(in: entries, inputText: text)
        else {
            guard state.entryViewLayout.pendingTypeScrollTargetId != nil else { return .none }
            return .send(.entryViewLayout(.view(.resetTypeScrollTarget)))
        }

        return .send(.entryViewLayout(.view(.setTypeScrollTarget(firstMatch))))
    }

    static func effect(
        for command: KeyCommand,
        state: FileManagerContentState,
        consumeNativeUndo: (() -> Bool)? = nil,
        consumeNativeRedo: (() -> Bool)? = nil,
        textResponderIsEditing: Bool? = nil,
    ) -> Effect<FileManagerContentAction> {
        if let effect = quickLookKeyEffect(for: command, state: state) { return effect }
        if let effect = deleteKeyEffect(for: command, state: state) { return effect }
        if let effect = renameKeyEffect(for: command, state: state) { return effect }
        if let movementEffect = selectionMovementEffect(for: command, state: state) { return movementEffect }
        if let effect = commandModifierEffect(
            for: command,
            state: state,
            consumeNativeUndo: consumeNativeUndo,
            consumeNativeRedo: consumeNativeRedo,
            textResponderIsEditing: textResponderIsEditing,
        ) { return effect }
        return .none
    }

    static func compositionPolicy(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> FileManagerKeyCommandCompositionPolicy {
        guard command.modifiers.contains(.command) else { return .preserveMarkedText }

        if command.keyCode == 51 {
            return state.entryViewLayout.selectedIds.isEmpty ? .preserveMarkedText : .cancelMarkedText
        }

        if command.modifiers.isDisjoint(with: [.option, .control]),
           command.charactersIgnoringModifiers == "z"
        {
            return state.composer.isPresented ? .preserveMarkedText : .cancelMarkedText
        }

        if command.characters == ".", command.modifiers.contains(.shift) {
            return .cancelMarkedText
        }

        if command.keyCode == 125,
           command.modifiers.isDisjoint(with: [.option, .control, .shift])
        {
            return state.entryViewLayout.selectedIds.isEmpty ? .preserveMarkedText : .cancelMarkedText
        }

        guard command.modifiers.isDisjoint(with: [.option, .control, .shift]) else {
            return .preserveMarkedText
        }

        switch command.charactersIgnoringModifiers {
        case "v":
            return .cancelMarkedText
        case "d":
            return state.entryViewLayout.selectedIds.isEmpty ? .preserveMarkedText : .cancelMarkedText
        default:
            return .preserveMarkedText
        }
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

        return .send(.entryViewLayout(.delegate(.executeCommand("navigation.quickLookSelectedItem"))))
    }

    private static func deleteKeyEffect(
        for command: KeyCommand,
        state _: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.keyCode == 51,
              command.modifiers.contains(.command)
        else {
            return nil
        }

        if command.modifiers.contains(.option) {
            return .send(.entryViewLayout(.delegate(.executeCommand(
                "mutation.deleteSelectedItemsImmediately",
            ))))
        }
        return .send(.entryViewLayout(.delegate(.executeCommand(
            "mutation.moveSelectedItemsToTrash",
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
        guard selectedIds.count == 1,
              let selectedId = selectedIds.first,
              let entry = commandEntries(state: state).first(where: { $0.id == selectedId })
        else { return .none }

        return .send(.entryViewLayout(.delegate(.startRename(item: entry, text: entry.name))))
    }

    private static func commandModifierEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
        consumeNativeUndo: (() -> Bool)?,
        consumeNativeRedo: (() -> Bool)?,
        textResponderIsEditing: Bool?,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.contains(.command) else { return nil }

        if command.modifiers.isDisjoint(with: [.option, .control]),
           command.charactersIgnoringModifiers == "z"
        {
            return undoRedoEffect(
                for: command,
                state: state,
                consumeNativeUndo: consumeNativeUndo,
                consumeNativeRedo: consumeNativeRedo,
                textResponderIsEditing: textResponderIsEditing
                    ?? ((consumeNativeUndo == nil && consumeNativeRedo == nil) ? isTextEditingResponder() : false),
            )
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
            return .send(.entryViewLayout(.delegate(.executeCommand("navigation.openSelectedItem"))))
        }

        guard command.modifiers.isDisjoint(with: [.option, .control, .shift]),
              let key = command.charactersIgnoringModifiers
        else {
            return nil
        }

        switch key {
        case "x":
            return .send(.entryViewLayout(.delegate(.executeCommand("clipboard.cutSelectedItems"))))

        case "c":
            return .send(.entryViewLayout(.delegate(.executeCommand("clipboard.copySelectedItems"))))

        case "v":
            return .send(.entryViewLayout(.delegate(.executeCommand("clipboard.pasteItems"))))

        case "d":
            return .send(.entryViewLayout(.delegate(.executeCommand("clipboard.duplicateSelectedItems"))))

        default:
            return nil
        }
    }

    private static func undoRedoEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
        consumeNativeUndo: (() -> Bool)?,
        consumeNativeRedo: (() -> Bool)?,
        textResponderIsEditing: Bool,
    ) -> Effect<FileManagerContentAction> {
        if state.composer.isPresented {
            return .none
        }

        if command.modifiers.contains(.shift) {
            if textResponderIsEditing {
                _ = consumeNativeRedo?() ?? sendNativeAction(redoSelector)
                return .none
            }
            if consumeNativeRedo?() == true {
                return .none
            }
            return .send(.delegate(.requestUndoRedo(.redo)))
        }

        if textResponderIsEditing {
            _ = consumeNativeUndo?() ?? sendNativeAction(undoSelector)
            return .none
        }
        if consumeNativeUndo?() == true {
            return .none
        }
        return .send(.delegate(.requestUndoRedo(.undo)))
    }

    private static func selectionMovementEffect(
        for command: KeyCommand,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction>? {
        guard command.modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }

        let isShiftPressed = command.modifiers.contains(.shift)

        switch command.keyCode {
        case 123 where state.entryViewLayout.mode == .list:
            return listHierarchyCollapseEffect(state: state)
        case 124 where state.entryViewLayout.mode == .list:
            return listHierarchyExpansionEffect(state: state)
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

    private static func listHierarchyExpansionEffect(
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard let entry = focusedVisibleEntry(state: state),
              entry.supportsListHierarchyExpansion,
              !state.entryViewLayout.hierarchy.expandedFolderIDs.contains(entry.id)
        else { return .none }
        return .send(.entryViewLayout(.hierarchy(.folderExpansionRequested(id: entry.id))))
    }

    private static func listHierarchyCollapseEffect(
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        guard let entry = focusedVisibleEntry(state: state),
              state.entryViewLayout.hierarchy.expandedFolderIDs.contains(entry.id)
        else { return .none }
        return .send(.entryViewLayout(.hierarchy(.folderCollapseRequested(id: entry.id))))
    }

    private static func focusedVisibleEntry(state: FileManagerContentState) -> EntryModel? {
        guard state.entryViewLayout.hierarchyProjectionIsActive,
              let focusedID = state.entryViewLayout.lastSelectedId ?? state.entryViewLayout.selectedIds.first
        else { return nil }
        return state.entryViewLayout
            .visibleSelectableEntries(isNormalDirectoryPage: isNormalDirectoryPage(state))
            .first { $0.id == focusedID }
    }

    private static func selectionOffsetEffect(
        offset: Int,
        isShiftPressed: Bool,
        state: FileManagerContentState,
    ) -> Effect<FileManagerContentAction> {
        .send(.entryViewLayout(.internal(.applySelectionOffset(
            offset: offset,
            isShiftPressed: isShiftPressed,
            orderedItemIds: state.entryViewLayout.visibleSelectableEntryIDs(
                isNormalDirectoryPage: isNormalDirectoryPage(state),
            ),
        ))))
    }

    private static func isNormalDirectoryPage(_ state: FileManagerContentState) -> Bool {
        if case .folder = state.navigation.navigationState {
            return true
        }
        return false
    }

    private static func commandEntries(state: FileManagerContentState) -> [EntryModel] {
        state.entryViewLayout.visibleSelectableEntries(
            isNormalDirectoryPage: isNormalDirectoryPage(state),
        )
    }

    /// type-scroll 후보 엔트리 목록. 계층형 목록 모드에서는 outline projection의
    /// visibleSelectableEntries(expanded folder를 반영)를, 그 외 flat/grouped 모드에서는
    /// collapsed group을 반영한 presentation.visibleEntries를 사용한다.
    private static func typeScrollCandidateEntries(state: FileManagerContentState) -> [EntryModel] {
        if state.entryViewLayout.hierarchyProjectionIsActive {
            return state.entryViewLayout.visibleSelectableEntries(
                isNormalDirectoryPage: isNormalDirectoryPage(state),
            )
        }
        return state.entryViewLayout.presentation.visibleEntries
    }

    private static func sendNativeAction(_ selector: Selector) -> Bool {
        MainActor.assumeIsolated {
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }

    private static func isTextEditingResponder() -> Bool {
        MainActor.assumeIsolated {
            guard let responder = NSApp?.keyWindow?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }
    }
}

import AppKit
import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>
    @FocusState private var isKeyCommandFocused: Bool
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    private var statusText: String {
        let total = store.fsItems.displayItems.count
        let selected = store.fsItems.selectedIds.count

        if selected == 0 {
            return "\(total) items"
        } else {
            return "\(selected) of \(total) selected"
        }
    }

    private var isCollectionSearching: Bool {
        let isSearching = store.composer.isLoadingSearch || store.composer.isLoadingFilters
        let hasContext = store.fsItems.isCollectionMode
            || store.pendingSearchQuery != nil
            || !store.composer.scopes.isEmpty
            || !store.composer.conditions.isEmpty
        return isSearching && hasContext
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if isCollectionSearching {
                    collectionLoadingView
                } else {
                    switch store.viewLayout {
                    case .list:
                        ContentPaneListView(store: store)
                    case .grid:
                        ContentPaneGridView(store: store)
                    }
                }

                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 1)
                breadcrumbStatusBar
            }

            KeyCommandView { event in
                handleKeyboardEvent(event)
            }
            .focusable()
            .focused($isKeyCommandFocused)
            .allowsHitTesting(false)
        }
        .onChange(of: store.fsItems.selectedIds) { _ in
            restoreKeyCommandFocus()
        }
        .onChange(of: store.fsItems.isRenaming) { isRenaming in
            if !isRenaming {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    restoreKeyCommandFocus()
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                restoreKeyCommandFocus()
            }
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    restoreKeyCommandFocus()
                },
        )
    }

    @ViewBuilder private var breadcrumbStatusBar: some View {
        GeometryReader { proxy in
            let totalWidth = max(proxy.size.width - 32, 0)
            let leftWidth = max(totalWidth * 0.5, 0)

            HStack(spacing: 0) {
                if !store.breadcrumbItems.isEmpty || store.selectedBreadcrumbItem != nil {
                    PathBreadcrumbView(
                        breadcrumbItems: store.breadcrumbItems,
                        selectedItem: nil,
                        availableWidth: leftWidth,
                        onNavigate: { path in store.send(.navigateTo(path)) },
                    )
                    .frame(width: leftWidth, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: leftWidth)
                }

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 20)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .frame(height: 24)
    }

    private var separatorColor: Color {
        Color.primary.opacity(0.12)
    }

    private var collectionLoadingView: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear

                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    private func restoreKeyCommandFocus() {
        isKeyCommandFocused = true
        restoreFileManagerFocus()
    }

    private func handleKeyboardEvent(_ event: NSEvent) {
        if handleEscapeKey(event) { return }
        if handleEnterKey(event) { return }
        if handleSpaceKey(event) { return }
        if handleCommandOptionKeys(event) { return }
        if handleDeleteKeys(event) { return }
        if handleArrowKeys(event) { return }
        handleCommandKeys(event)
    }

    private func handleEscapeKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, store.fsItems.isRenaming else { return false }
        store.send(.fsItems(.cancelRename))
        return true
    }

    private func handleEnterKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36,
              event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        else { return false }

        if store.fsItems.isRenaming {
            store.send(.fsItems(.commitRename))
            return true
        }

        if store.fsItems.selectedIds.count == 1,
           let selectedId = store.fsItems.selectedIds.first
        {
            store.send(.fsItems(.startRename(id: selectedId)))
        }
        return true
    }

    private func handleSpaceKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49,
              event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        else { return false }

        if store.canQuickLookSelectedItem {
            store.send(.quickLookSelectedItem)
        }
        return true
    }

    private func handleCommandOptionKeys(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.option)
        else { return false }

        if event.keyCode == 125 {
            if store.fsItems.selectedIds.count == 1,
               let selectedId = store.fsItems.selectedIds.first,
               let selectedItem = store.fsItems.displayItems.first(where: { $0.id == selectedId }),
               selectedItem.isDirectory
            {
                AppDelegate.shared?.createNewTab(path: selectedItem.fullPath)
            }
            return true
        }

        return false
    }

    private func handleDeleteKeys(_ event: NSEvent) -> Bool {
        guard event.keyCode == 51,
              event.modifierFlags.contains(.command)
        else { return false }

        if event.modifierFlags.contains(.option) {
            if !store.fsItems.selectedIds.isEmpty {
                store.send(.deleteSelectedItemsImmediately)
            }
            return true
        } else {
            if !store.fsItems.selectedIds.isEmpty {
                store.send(.moveSelectedItemsToTrash)
            }
            return true
        }
    }

    private func handleArrowKeys(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control]) else { return false }

        let isShiftPressed = event.modifierFlags.contains(.shift)

        @MainActor
        func move(_ offset: Int) {
            if offset == 1 {
                store.send(.fsItems(.selectNextItem(isShiftPressed: isShiftPressed)))
            } else if offset == -1 {
                store.send(.fsItems(.selectPreviousItem(isShiftPressed: isShiftPressed)))
            } else {
                store.send(.fsItems(.selectByOffset(offset: offset, isShiftPressed: isShiftPressed)))
            }
        }

        switch event.keyCode {
        case 123 where store.viewLayout == .grid: move(-1)
        case 124 where store.viewLayout == .grid: move(+1)
        case 126 where store.viewLayout == .grid:
            let columnCount = store.fsItems.gridColumnCount
            move(-columnCount)
        case 125 where store.viewLayout == .grid:
            let columnCount = store.fsItems.gridColumnCount
            move(+columnCount)
        case 126: move(-1)
        case 125: move(+1)
        default: return false
        }
        return true
    }

    private func handleCommandKeys(_ event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { return }

        if handleUndoRedoKeys(event) { return }

        if event.characters == ".", event.modifierFlags.contains(.shift) {
            store.send(.toggleShowHiddenFiles)
        } else if let number = Int(event.characters ?? ""), (1 ... 9).contains(number) {
            AppDelegate.shared?.selectTab(at: number - 1)
        } else if event.characters == "0" {
            AppDelegate.shared?.selectTab(at: 9)
        }
    }

    private func handleUndoRedoKeys(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.option, .control]),
              event.charactersIgnoringModifiers == "z"
        else { return false }

        if store.composer.isPresented {
            return false
        }

        if event.modifierFlags.contains(.shift) {
            if canRedoInTextResponder(),
               NSApp.sendAction(Self.redoSelector, to: nil, from: nil)
            {
                return true
            }
            store.send(.fsItems(.requestRedo))
            return true
        }

        if canUndoInTextResponder(),
           NSApp.sendAction(Self.undoSelector, to: nil, from: nil)
        {
            return true
        }
        store.send(.fsItems(.requestUndo))
        return true
    }

    private func isTextEditingResponder() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func canUndoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager?.canUndo == true
    }

    private func canRedoInTextResponder() -> Bool {
        guard isTextEditingResponder() else { return false }
        return (NSApp.keyWindow?.firstResponder as? NSResponder)?.undoManager?.canRedo == true
    }
}

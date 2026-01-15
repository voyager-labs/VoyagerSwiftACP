import AppKit
import ComposableArchitecture
import SwiftUI

// swiftlint:disable type_body_length
struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    @Dependency(\.fileManagerWindowClient)
    private var fileManagerWindowClient
    @Dependency(\.entryClient)
    private var entryClient
    @Dependency(\.workspaceClient)
    private var workspaceClient
    @Dependency(\.sidebarClient)
    private var sidebarClient
    @FocusState private var isKeyCommandFocused: Bool
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    private var statusText: String {
        let total = store.entries.displayItems.count
        let selected = store.entries.selectedIds.count

        if selected == 0 {
            return "\(total) items"
        } else {
            return "\(selected) of \(total) selected"
        }
    }

    private var isCollectionSearching: Bool {
        let isSearching = store.composer.isLoadingSearch || store.composer.isLoadingFilters
        let hasContext = store.entries.isCollectionMode
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
        .onChange(of: store.entries.selectedIds) { _ in
            restoreKeyCommandFocus()
        }
        .onChange(of: store.entries.isRenaming) { isRenaming in
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
                let breadcrumbItems = breadcrumbItems(for: store.state)
                let selectedBreadcrumbItem = selectedBreadcrumbItem(for: store.state)
                if !breadcrumbItems.isEmpty || selectedBreadcrumbItem != nil {
                    PathBreadcrumbView(
                        breadcrumbItems: breadcrumbItems,
                        selectedItem: selectedBreadcrumbItem,
                        availableWidth: leftWidth,
                        onNavigate: { path in store.send(.navigateTo(path)) },
                        onOpenInNewWindow: { path in
                            Task {
                                _ = await fileManagerWindowClient.openWindow(path)
                            }
                        },
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
        guard event.keyCode == 53, store.entries.isRenaming else { return false }
        store.send(.entries(.cancelRename))
        return true
    }

    private func handleEnterKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36,
              event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        else { return false }

        if store.entries.isRenaming {
            store.send(.entries(.commitRename))
            return true
        }

        if store.entries.selectedIds.count == 1,
           let selectedId = store.entries.selectedIds.first
        {
            store.send(.entries(.startRename(id: selectedId)))
        }
        return true
    }

    private func handleSpaceKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49,
              event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        else { return false }

        if store.canQuickLookSelectedItem {
            store.send(.entries(.quickLookSelectedItem))
        }
        return true
    }

    private func handleCommandOptionKeys(_ event: NSEvent) -> Bool {
        _ = event
        return false
    }

    private func handleDeleteKeys(_ event: NSEvent) -> Bool {
        guard event.keyCode == 51,
              event.modifierFlags.contains(.command)
        else { return false }

        if event.modifierFlags.contains(.option) {
            if !store.entries.selectedIds.isEmpty {
                store.send(.entries(.deleteSelectedItemsImmediately))
            }
            return true
        } else {
            if !store.entries.selectedIds.isEmpty {
                store.send(.entries(.moveSelectedItemsToTrash))
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
                store.send(.entries(.selectNextItem(isShiftPressed: isShiftPressed)))
            } else if offset == -1 {
                store.send(.entries(.selectPreviousItem(isShiftPressed: isShiftPressed)))
            } else {
                store.send(.entries(.selectByOffset(offset: offset, isShiftPressed: isShiftPressed)))
            }
        }

        switch event.keyCode {
        case 123 where store.viewLayout == .grid: move(-1)
        case 124 where store.viewLayout == .grid: move(+1)
        case 126 where store.viewLayout == .grid:
            let columnCount = store.entries.gridColumnCount
            move(-columnCount)
        case 125 where store.viewLayout == .grid:
            let columnCount = store.entries.gridColumnCount
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
            store.send(.entries(.requestRedo))
            return true
        }

        if canUndoInTextResponder(),
           NSApp.sendAction(Self.undoSelector, to: nil, from: nil)
        {
            return true
        }
        store.send(.entries(.requestUndo))
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

    // swiftlint:disable function_body_length
    private func breadcrumbItems(for state: FileManagerFeature.State) -> [BreadcrumbUtils.Item] {
        switch state.navigationState {
        case .recents, .tags:
            return []
        case .computer:
            if state.entries.selectedIds.count == 1,
               let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first }),
               selectedItem.fullPath == "/"
            {
                return []
            }
            let computerName = sidebarClient.computerName()
            return [
                BreadcrumbUtils.Item(
                    path: computerName,
                    name: computerName,
                    icon: NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/"),
                ),
            ]
        case let .folder(path):
            let trashPath = entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path
            let iCloudDrivePath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            let cloudStoragePath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/CloudStorage")

            let isTrashFolder: Bool = if let trashPath {
                path == trashPath || path.hasPrefix(trashPath + "/")
            } else {
                false
            }

            let paths: [String] = if let rootPath = BreadcrumbUtils.findSpecialRootPath(
                for: path,
                isTrashFolder: isTrashFolder,
                trashPath: trashPath,
                iCloudDrivePath: iCloudDrivePath,
                cloudStoragePath: cloudStoragePath,
            ) {
                BreadcrumbUtils.buildBreadcrumbPaths(from: rootPath, to: path)
            } else {
                BreadcrumbUtils.buildBreadcrumbPathsForStandardPath(path)
            }

            let computerName = sidebarClient.computerName()
            return paths.map { breadcrumbPath in
                let name: String
                let icon: NSImage

                if breadcrumbPath == computerName {
                    name = computerName
                    icon = NSImage(named: "NSComputer") ?? workspaceClient.iconForFile("/")
                } else {
                    name = entryClient.displayName(breadcrumbPath)
                    if let trashPath = entryClient.urlsForDirectory(.trashDirectory, .userDomainMask).first?.path,
                       breadcrumbPath == trashPath
                    {
                        icon = NSImage(named: NSImage.trashFullName) ?? workspaceClient.iconForFile(breadcrumbPath)
                    } else {
                        icon = workspaceClient.iconForFile(breadcrumbPath)
                    }
                }

                return BreadcrumbUtils.Item(path: breadcrumbPath, name: name, icon: icon)
            }
        case .collection:
            return []
        }
    }

    private func selectedBreadcrumbItem(for state: FileManagerFeature.State) -> BreadcrumbUtils.Item? {
        guard state.entries.selectedIds.count == 1,
              let selectedItem = state.entries.displayItems.first(where: { $0.id == state.entries.selectedIds.first })
        else { return nil }

        let selectedBreadcrumb = BreadcrumbUtils.Item(entry: selectedItem, workspaceClient: workspaceClient)

        if selectedBreadcrumb.fullPath == state.currentPath {
            return nil
        }

        return selectedBreadcrumb
    }
    // swiftlint:enable function_body_length
}

// swiftlint:enable type_body_length

import ComposableArchitecture
import Foundation
import IdentifiedCollections
import SwiftUI

func sendWithSelection(
    _ item: FSItem,
    fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
    action: @escaping () -> Void
) {
    if !fsStore.selectedIds.contains(item.id) {
        fsStore.send(.selectItem(id: item.id, isCommandPressed: false, isShiftPressed: false))
    }
    action()
}

func calculateCompressExtractOptions(
    selectedItems: IdentifiedArrayOf<FSItem>
) -> (showCompress: Bool, showExtract: Bool) {
    let containsZipFiles = selectedItems.contains { $0.fileExtension.lowercased() == "zip" }
    let containsNonZipFiles = selectedItems.contains { $0.fileExtension.lowercased() != "zip" }

    let showCompress = !containsZipFiles
    let showExtract = containsZipFiles && !containsNonZipFiles

    return (showCompress, showExtract)
}

struct FSItemContextMenuHandlers {
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onOpenInNewTab: (Bool) -> Void
    let onQuickLook: () -> Void
    let onOpenWithApp: (String?, Bool) -> Void
    let onRenameUpdate: (String) -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onStartDrag: () -> Void
    let onDrop: ([NSItemProvider], String) -> Void
    let onLoadApplications: () -> Void
    let onPutBack: (() -> Void)?
    let onMoveToTrash: () -> Void
    let onDeleteImmediately: () -> Void
    let onEmptyTrash: () -> Void
    let onRename: () -> Void
    let onCompress: () -> Void
    let onDuplicate: () -> Void
    let onExtract: () -> Void
    let onCopy: () -> Void
    let onCut: () -> Void
    let onToggleTag: (String) -> Void
}

// swiftlint:disable function_body_length
func makeContextMenuHandlers(
    item: FSItem,
    fsStore: Store<FSItemsFeature.State, FSItemsFeature.Action>,
    saveScrollPosition: @escaping () -> Void,
    isTrashFolder: Bool,
    onEmptyTrash: @escaping () -> Void
) -> FSItemContextMenuHandlers {
    let onSelect: () -> Void = {
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        let isShiftPressed = NSEvent.modifierFlags.contains(.shift)
        fsStore.send(.selectItem(
            id: item.id,
            isCommandPressed: isCommandPressed,
            isShiftPressed: isShiftPressed
        ))
    }

    let onOpen: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            saveScrollPosition()
            fsStore.send(.openSelectedItem)
        })
    }

    let onOpenInNewTab: (Bool) -> Void = { shouldOpenInNewWindow in
        if item.isDirectory {
            if shouldOpenInNewWindow {
                AppDelegate.shared?.createNewWindow(path: item.fullPath)
            } else {
                AppDelegate.shared?.createNewTab(path: item.fullPath)
            }
        }
    }

    let onQuickLook: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.quickLookSelectedItem)
        })
    }

    let onOpenWithApp: (String?, Bool) -> Void = { bundleID, shouldSetAsDefault in
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: shouldSetAsDefault))
        })
    }

    let onRenameUpdate: (String) -> Void = { text in
        fsStore.send(.updateRenamingText(text))
    }

    let onRenameCommit: () -> Void = {
        fsStore.send(.commitRename)
    }

    let onRenameCancel: () -> Void = {
        fsStore.send(.cancelRename)
    }

    let onStartDrag: () -> Void = {
        let dragPaths = fsStore.selectedIds.isEmpty
            ? [item.fullPath]
            : fsStore.items.filter { fsStore.selectedIds.contains($0.id) }
            .map { $0.fullPath }
        fsStore.send(.startDrag(paths: dragPaths))
    }

    let onDrop: ([NSItemProvider], String) -> Void = { providers, folderPath in
        fsStore.send(.handleDrop(providers: providers, destinationPath: folderPath))
    }

    let onLoadApplications: () -> Void = {
        fsStore.send(.operations(.loadApplicationsForFile(file: item)))
    }

    let onPutBack: (() -> Void)? = isTrashFolder ? {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.putBackSelectedItems)
        })
    } : nil

    let onMoveToTrash: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.moveSelectedItemsToTrash)
        })
    }

    let onDeleteImmediately: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.deleteSelectedItemsImmediately)
        })
    }

    let onRename: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.startRename(id: item.id))
        })
    }

    let onCompress: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.compressSelectedItems)
        })
    }

    let onDuplicate: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.duplicateSelectedItems)
        })
    }

    let onExtract: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.extractSelectedItem)
        })
    }

    let onCopy: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.copySelectedItems)
        })
    }

    let onCut: () -> Void = {
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.cutSelectedItems)
        })
    }

    let onToggleTag: (String) -> Void = { tag in
        sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.toggleTagForSelectedItem(tag: tag))
        })
    }

    return FSItemContextMenuHandlers(
        onSelect: onSelect,
        onOpen: onOpen,
        onOpenInNewTab: onOpenInNewTab,
        onQuickLook: onQuickLook,
        onOpenWithApp: onOpenWithApp,
        onRenameUpdate: onRenameUpdate,
        onRenameCommit: onRenameCommit,
        onRenameCancel: onRenameCancel,
        onStartDrag: onStartDrag,
        onDrop: onDrop,
        onLoadApplications: onLoadApplications,
        onPutBack: onPutBack,
        onMoveToTrash: onMoveToTrash,
        onDeleteImmediately: onDeleteImmediately,
        onEmptyTrash: onEmptyTrash,
        onRename: onRename,
        onCompress: onCompress,
        onDuplicate: onDuplicate,
        onExtract: onExtract,
        onCopy: onCopy,
        onCut: onCut,
        onToggleTag: onToggleTag
    )
}

// swiftlint:enable function_body_length

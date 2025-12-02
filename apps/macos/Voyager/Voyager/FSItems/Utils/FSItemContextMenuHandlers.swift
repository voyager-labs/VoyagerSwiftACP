import ComposableArchitecture
import Foundation
import IdentifiedCollections
import SwiftUI

struct FSItemContextMenuHandlers {
    let onSelect: (Bool, Bool) -> Void
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
    let onLoadCommonApplications: (() -> Void)?
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
    let onSelect: (Bool, Bool) -> Void = { isCommandPressed, isShiftPressed in
        fsStore.send(.selectItem(
            id: item.id,
            isCommandPressed: isCommandPressed,
            isShiftPressed: isShiftPressed
        ))
    }

    let onOpen: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
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
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.quickLookSelectedItem)
        })
    }

    let onOpenWithApp: (String?, Bool) -> Void = { bundleID, shouldSetAsDefault in
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
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

    let onLoadCommonApplications: (() -> Void)? = {
        let selectedItems = Array(fsStore.items.filter { fsStore.selectedIds.contains($0.id) })
        let selectedFiles = selectedItems.filter { !$0.isDirectory }
        guard selectedFiles.count > 1 else { return }
        fsStore.send(.operations(.loadCommonApplicationsForFiles(files: selectedFiles)))
    }

    let onPutBack: (() -> Void)? = isTrashFolder ? {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.putBackSelectedItems)
        })
    } : nil

    let onMoveToTrash: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.moveSelectedItemsToTrash)
        })
    }

    let onDeleteImmediately: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.deleteSelectedItemsImmediately)
        })
    }

    let onRename: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.startRename(id: item.id))
        })
    }

    let onCompress: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.compressSelectedItems)
        })
    }

    let onDuplicate: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.duplicateSelectedItems)
        })
    }

    let onExtract: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.extractSelectedItem)
        })
    }

    let onCopy: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.copySelectedItems)
        })
    }

    let onCut: () -> Void = {
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.cutSelectedItems)
        })
    }

    let onToggleTag: (String) -> Void = { tag in
        FSItemContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
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
        onLoadCommonApplications: onLoadCommonApplications,
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

import ComposableArchitecture
import Foundation
import IdentifiedCollections
import SwiftUI

struct EntryContextMenuContext {
    let item: Entry
    let fsStore: Store<EntriesFeature.State, EntriesFeature.Action>
    let saveScrollPosition: () -> Void
    let shareAnchorProvider: () -> CGPoint?
    let isTrashFolder: Bool
    let onEmptyTrash: () -> Void
    let openWindow: (String) -> Void
}

struct EntryContextMenuHandlers {
    let onSelect: (Bool, Bool) -> Void
    let onOpen: () -> Void
    let onOpenInNewTab: (Bool) -> Void
    let onQuickLook: () -> Void
    let onGetInfo: () -> Void
    let onShare: () -> Void
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
    let onCreateAlias: () -> Void
    let onExtract: () -> Void
    let onCopy: () -> Void
    let onCopyAbsolutePaths: () -> Void
    let onCopyURLs: () -> Void
    let onCut: () -> Void
    let onToggleTag: (String) -> Void
    let onPerformService: (String) -> Void
    let onRevealInFinder: () -> Void
}

// swiftlint:disable:next function_body_length
func makeContextMenuHandlers(context: EntryContextMenuContext) -> EntryContextMenuHandlers {
    let item = context.item
    let fsStore = context.fsStore
    let saveScrollPosition = context.saveScrollPosition
    let shareAnchorProvider = context.shareAnchorProvider
    let isTrashFolder = context.isTrashFolder
    let onEmptyTrash = context.onEmptyTrash
    let openWindow = context.openWindow
    let onSelect: (Bool, Bool) -> Void = { isCommandPressed, isShiftPressed in
        if !isCommandPressed, !isShiftPressed, fsStore.selectedIds.contains(item.id), fsStore.selectedIds.count > 1 {
            restoreFileManagerFocus()
            return
        }

        fsStore.send(.selectItem(
            id: item.id,
            isCommandPressed: isCommandPressed,
            isShiftPressed: isShiftPressed,
        ))
        restoreFileManagerFocus()
    }

    let onOpen: () -> Void = {
        let currentSelectedIds = fsStore.selectedIds

        if currentSelectedIds.count >= 1 {
            saveScrollPosition()
            fsStore.send(.openSelectedItem)
        } else {
            EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
                saveScrollPosition()
                fsStore.send(.openSelectedItem)
            })
        }
    }

    let onOpenInNewTab: (Bool) -> Void = { _ in
        if item.isDirectory {
            openWindow(item.fullPath)
        }
    }

    let onQuickLook: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.quickLookSelectedItem)
        })
    }

    let onGetInfo: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.getInfoForSelectedItems)
        })
    }

    let onShare: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.shareSelectedItems(anchor: shareAnchorProvider()))
        })
    }

    let onOpenWithApp: (String?, Bool) -> Void = { bundleID, shouldSetAsDefault in
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
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
            .map(\.fullPath)
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
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.putBackSelectedItems)
        })
    } : nil

    let onMoveToTrash: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.moveSelectedItemsToTrash)
        })
    }

    let onDeleteImmediately: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.deleteSelectedItemsImmediately)
        })
    }

    let onRename: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.startRename(id: item.id))
        })
    }

    let onCompress: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.compressSelectedItems)
        })
    }

    let onDuplicate: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.duplicateSelectedItems)
        })
    }

    let onCreateAlias: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.createAliasForSelectedItems)
        })
    }

    let onExtract: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.extractSelectedItem)
        })
    }

    let onCopy: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.copySelectedItems)
        })
    }

    let onCut: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.cutSelectedItems)
        })
    }

    let onCopyAbsolutePaths: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.copySelectedAbsolutePaths)
        })
    }

    let onCopyURLs: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.copySelectedURLs)
        })
    }

    let onToggleTag: (String) -> Void = { tag in
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.toggleTagForSelectedItem(tag: tag))
        })
    }

    let onPerformService: (String) -> Void = { serviceName in
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.performService(serviceName: serviceName))
        })
    }

    let onRevealInFinder: () -> Void = {
        EntryContextMenuUtils.sendWithSelection(item, fsStore: fsStore, action: {
            fsStore.send(.revealSelectedItemsInFinder)
        })
    }

    return EntryContextMenuHandlers(
        onSelect: onSelect,
        onOpen: onOpen,
        onOpenInNewTab: onOpenInNewTab,
        onQuickLook: onQuickLook,
        onGetInfo: onGetInfo,
        onShare: onShare,
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
        onCreateAlias: onCreateAlias,
        onExtract: onExtract,
        onCopy: onCopy,
        onCopyAbsolutePaths: onCopyAbsolutePaths,
        onCopyURLs: onCopyURLs,
        onCut: onCut,
        onToggleTag: onToggleTag,
        onPerformService: onPerformService,
        onRevealInFinder: onRevealInFinder,
    )
}

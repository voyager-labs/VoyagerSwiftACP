import AppKit
import ComposableArchitecture

final class EntryContextMenuCoordinator: NSObject {
    var onOpenSelectedItem: () -> Void = {}
    var onOpenSelectedItemInNewTab: (String) -> Void = { _ in }
    var onQuickLookSelectedItem: () -> Void = {}
    var onGetInfoForSelectedItems: () -> Void = {}
    var onShareSelectedItems: () -> Void = {}
    var onRevealSelectedItemsInFinder: () -> Void = {}
    var onCopySelectedItems: () -> Void = {}
    var onCopySelectedAbsolutePaths: () -> Void = {}
    var onCopySelectedURLs: () -> Void = {}
    var onCutSelectedItems: () -> Void = {}
    var onPasteItems: () -> Void = {}
    var onStartRename: () -> Void = {}
    var onDuplicateSelectedItems: () -> Void = {}
    var onCreateAliasForSelectedItems: () -> Void = {}
    var onCompressSelectedItems: () -> Void = {}
    var onExtractSelectedItem: () -> Void = {}
    var onMoveSelectedItemsToTrash: () -> Void = {}
    var onDeleteSelectedItemsImmediately: () -> Void = {}
    var onPutBackSelectedItems: () -> Void = {}
    var onEmptyTrash: () -> Void = {}
    var onOpenWithSelectedItem: (String?) -> Void = { _ in }
    var onToggleTagForSelectedItem: (String) -> Void = { _ in }

    @objc
    func contextMenuOpenSelectedItem() {
        onOpenSelectedItem()
    }

    @objc
    func contextMenuOpenSelectedItemInNewTab(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onOpenSelectedItemInNewTab(path)
    }

    @objc
    func contextMenuQuickLookSelectedItem() {
        onQuickLookSelectedItem()
    }

    @objc
    func contextMenuGetInfoForSelectedItems() {
        onGetInfoForSelectedItems()
    }

    @objc
    func contextMenuShareSelectedItems() {
        onShareSelectedItems()
    }

    @objc
    func contextMenuRevealSelectedItemsInFinder() {
        onRevealSelectedItemsInFinder()
    }

    @objc
    func contextMenuCopySelectedItems() {
        onCopySelectedItems()
    }

    @objc
    func contextMenuCopySelectedAbsolutePaths() {
        onCopySelectedAbsolutePaths()
    }

    @objc
    func contextMenuCopySelectedURLs() {
        onCopySelectedURLs()
    }

    @objc
    func contextMenuCutSelectedItems() {
        onCutSelectedItems()
    }

    @objc
    func contextMenuPasteItems() {
        onPasteItems()
    }

    @objc
    func contextMenuStartRename() {
        onStartRename()
    }

    @objc
    func contextMenuDuplicateSelectedItems() {
        onDuplicateSelectedItems()
    }

    @objc
    func contextMenuCreateAliasForSelectedItems() {
        onCreateAliasForSelectedItems()
    }

    @objc
    func contextMenuCompressSelectedItems() {
        onCompressSelectedItems()
    }

    @objc
    func contextMenuExtractSelectedItem() {
        onExtractSelectedItem()
    }

    @objc
    func contextMenuMoveSelectedItemsToTrash() {
        onMoveSelectedItemsToTrash()
    }

    @objc
    func contextMenuDeleteSelectedItemsImmediately() {
        onDeleteSelectedItemsImmediately()
    }

    @objc
    func contextMenuPutBackSelectedItems() {
        onPutBackSelectedItems()
    }

    @objc
    func contextMenuEmptyTrash() {
        onEmptyTrash()
    }

    @objc
    func contextMenuOpenWithOther() {
        onOpenWithSelectedItem(nil)
    }

    @objc
    func contextMenuOpenWithApp(_ sender: NSMenuItem) {
        let bundleID = sender.representedObject as? String
        onOpenWithSelectedItem(bundleID)
    }

    @objc
    func contextMenuToggleTag(_ sender: NSMenuItem) {
        guard let tagName = sender.representedObject as? String else { return }
        onToggleTagForSelectedItem(tagName)
    }
}

@MainActor
extension EntryContextMenuCoordinator {
    struct Context {
        let adapter: EntryViewLayoutAdapter
        let currentPath: () -> String
        let selectedItemId: () -> String?
        let contextMenuAnchor: () -> CGPoint?
        let saveScrollPosition: () -> Void
    }

    // swiftlint:disable function_body_length
    static func make(context: Context) -> EntryContextMenuCoordinator {
        let controller = EntryContextMenuCoordinator()

        controller.onOpenSelectedItem = {
            context.saveScrollPosition()
            context.adapter.actions.openSelectedItem()
        }
        controller.onOpenSelectedItemInNewTab = { path in
            context.adapter.actions.openPathInNewTab(path)
        }
        controller.onQuickLookSelectedItem = {
            context.adapter.actions.quickLookSelectedItem()
        }
        controller.onGetInfoForSelectedItems = {
            context.adapter.actions.getInfoForSelectedItems()
        }
        controller.onShareSelectedItems = {
            context.adapter.actions.shareSelectedItems(context.contextMenuAnchor())
        }
        controller.onRevealSelectedItemsInFinder = {
            context.adapter.actions.revealSelectedItemsInFinder()
        }
        controller.onCopySelectedItems = {
            context.adapter.actions.copySelectedItems()
        }
        controller.onCopySelectedAbsolutePaths = {
            context.adapter.actions.copySelectedAbsolutePaths()
        }
        controller.onCopySelectedURLs = {
            context.adapter.actions.copySelectedURLs()
        }
        controller.onCutSelectedItems = {
            context.adapter.actions.cutSelectedItems()
        }
        controller.onPasteItems = {
            context.adapter.actions.pasteItems(context.currentPath())
        }
        controller.onStartRename = {
            guard let id = context.selectedItemId() else { return }
            context.adapter.actions.startRename(id)
        }
        controller.onDuplicateSelectedItems = {
            context.adapter.actions.duplicateSelectedItems()
        }
        controller.onCreateAliasForSelectedItems = {
            context.adapter.actions.createAliasForSelectedItems()
        }
        controller.onCompressSelectedItems = {
            context.adapter.actions.compressSelectedItems()
        }
        controller.onExtractSelectedItem = {
            context.adapter.actions.extractSelectedItem()
        }
        controller.onMoveSelectedItemsToTrash = {
            context.adapter.actions.moveSelectedItemsToTrash()
        }
        controller.onDeleteSelectedItemsImmediately = {
            context.adapter.actions.deleteSelectedItemsImmediately()
        }
        controller.onPutBackSelectedItems = {
            context.adapter.actions.putBackSelectedItems()
        }
        controller.onEmptyTrash = {
            context.adapter.actions.emptyTrash()
        }
        controller.onOpenWithSelectedItem = { bundleID in
            context.adapter.actions.openWithSelectedItem(bundleID, false)
        }
        controller.onToggleTagForSelectedItem = { tagName in
            context.adapter.actions.toggleTagForSelectedItem(tagName)
        }

        return controller
    }
    // swiftlint:enable function_body_length
}

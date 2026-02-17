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
        let contentStore: StoreOf<FileManagerContentFeature>
        let fileManagerWindowClient: FileManagerWindowClient
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
            context.contentStore.send(.entries(.openSelectedItem))
        }
        controller.onOpenSelectedItemInNewTab = { path in
            Task {
                await context.fileManagerWindowClient.openPathInNewTab(path)
            }
        }
        controller.onQuickLookSelectedItem = {
            context.contentStore.send(.entries(.quickLookSelectedItem))
        }
        controller.onGetInfoForSelectedItems = {
            context.contentStore.send(.entries(.getInfoForSelectedItems))
        }
        controller.onShareSelectedItems = {
            context.contentStore.send(.entries(.shareSelectedItems(anchor: context.contextMenuAnchor())))
        }
        controller.onRevealSelectedItemsInFinder = {
            context.contentStore.send(.entries(.revealSelectedItemsInFinder))
        }
        controller.onCopySelectedItems = {
            context.contentStore.send(.entries(.copySelectedItems))
        }
        controller.onCopySelectedAbsolutePaths = {
            context.contentStore.send(.entries(.copySelectedAbsolutePaths))
        }
        controller.onCopySelectedURLs = {
            context.contentStore.send(.entries(.copySelectedURLs))
        }
        controller.onCutSelectedItems = {
            context.contentStore.send(.entries(.cutSelectedItems))
        }
        controller.onPasteItems = {
            context.contentStore.send(.entries(.pasteItems(destinationPath: context.currentPath())))
        }
        controller.onStartRename = {
            guard let id = context.selectedItemId() else { return }
            context.contentStore.send(.entries(.startRename(id: id)))
        }
        controller.onDuplicateSelectedItems = {
            context.contentStore.send(.entries(.duplicateSelectedItems))
        }
        controller.onCreateAliasForSelectedItems = {
            context.contentStore.send(.entries(.createAliasForSelectedItems))
        }
        controller.onCompressSelectedItems = {
            context.contentStore.send(.entries(.compressSelectedItems))
        }
        controller.onExtractSelectedItem = {
            context.contentStore.send(.entries(.extractSelectedItem))
        }
        controller.onMoveSelectedItemsToTrash = {
            context.contentStore.send(.entries(.moveSelectedItemsToTrash))
        }
        controller.onDeleteSelectedItemsImmediately = {
            context.contentStore.send(.entries(.deleteSelectedItemsImmediately))
        }
        controller.onPutBackSelectedItems = {
            context.contentStore.send(.entries(.putBackSelectedItems))
        }
        controller.onEmptyTrash = {
            context.contentStore.send(.entries(.emptyTrash))
        }
        controller.onOpenWithSelectedItem = { bundleID in
            context.contentStore.send(.entries(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: false)))
        }
        controller.onToggleTagForSelectedItem = { tagName in
            context.contentStore.send(.entries(.toggleTagForSelectedItem(tag: tagName)))
        }

        return controller
    }
    // swiftlint:enable function_body_length
}

import AppKit
import ComposableArchitecture

final class EntryContextMenuController: NSObject {
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
extension EntryContextMenuController {
    struct Context {
        let fsStore: StoreOf<EntryFeature>
        let fileManagerWindowClient: FileManagerWindowClient
        let currentPath: () -> String
        let selectedItemId: () -> String?
        let contextMenuAnchor: () -> CGPoint?
        let saveScrollPosition: () -> Void
    }

    // swiftlint:disable function_body_length
    static func make(context: Context) -> EntryContextMenuController {
        let controller = EntryContextMenuController()

        controller.onOpenSelectedItem = {
            context.saveScrollPosition()
            context.fsStore.send(.openSelectedItem)
        }
        controller.onOpenSelectedItemInNewTab = { path in
            Task {
                await context.fileManagerWindowClient.openPathInNewTab(path)
            }
        }
        controller.onQuickLookSelectedItem = {
            context.fsStore.send(.quickLookSelectedItem)
        }
        controller.onGetInfoForSelectedItems = {
            context.fsStore.send(.getInfoForSelectedItems)
        }
        controller.onShareSelectedItems = {
            context.fsStore.send(.shareSelectedItems(anchor: context.contextMenuAnchor()))
        }
        controller.onRevealSelectedItemsInFinder = {
            context.fsStore.send(.revealSelectedItemsInFinder)
        }
        controller.onCopySelectedItems = {
            context.fsStore.send(.copySelectedItems)
        }
        controller.onCopySelectedAbsolutePaths = {
            context.fsStore.send(.copySelectedAbsolutePaths)
        }
        controller.onCopySelectedURLs = {
            context.fsStore.send(.copySelectedURLs)
        }
        controller.onCutSelectedItems = {
            context.fsStore.send(.cutSelectedItems)
        }
        controller.onPasteItems = {
            context.fsStore.send(.pasteItems(destinationPath: context.currentPath()))
        }
        controller.onStartRename = {
            guard let id = context.selectedItemId() else { return }
            context.fsStore.send(.startRename(id: id))
        }
        controller.onDuplicateSelectedItems = {
            context.fsStore.send(.duplicateSelectedItems)
        }
        controller.onCreateAliasForSelectedItems = {
            context.fsStore.send(.createAliasForSelectedItems)
        }
        controller.onCompressSelectedItems = {
            context.fsStore.send(.compressSelectedItems)
        }
        controller.onExtractSelectedItem = {
            context.fsStore.send(.extractSelectedItem)
        }
        controller.onMoveSelectedItemsToTrash = {
            context.fsStore.send(.moveSelectedItemsToTrash)
        }
        controller.onDeleteSelectedItemsImmediately = {
            context.fsStore.send(.deleteSelectedItemsImmediately)
        }
        controller.onPutBackSelectedItems = {
            context.fsStore.send(.putBackSelectedItems)
        }
        controller.onEmptyTrash = {
            context.fsStore.send(.emptyTrash)
        }
        controller.onOpenWithSelectedItem = { bundleID in
            context.fsStore.send(.openWithSelectedItem(bundleID: bundleID, shouldSetAsDefault: false))
        }
        controller.onToggleTagForSelectedItem = { tagName in
            context.fsStore.send(.toggleTagForSelectedItem(tag: tagName))
        }

        return controller
    }
    // swiftlint:enable function_body_length
}

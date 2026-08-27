@preconcurrency import AppKit
import ComposableArchitecture
import CoreGraphics
import UniformTypeIdentifiers
import VoyagerEntitiesEntry

@MainActor
final class EntryContextMenuCoordinator: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let store: StoreOf<EntryViewLayoutFeature>
    private let target: EntryContextMenuTarget
    private weak var anchorView: NSView?
    private let anchorScreenPoint: CGPoint?
    private var popover: NSPopover?
    private var popoverController: EntryTagsPopoverViewController?
    private var pendingTagSpecs: [EntryContextMenuTagSpec]?
    private var openWithObservation: ObserveToken?

    init(
        store: StoreOf<EntryViewLayoutFeature>,
        target: EntryContextMenuTarget,
        anchorView: NSView?,
        anchorScreenPoint: CGPoint? = nil,
    ) {
        self.store = store
        self.target = target
        self.anchorView = anchorView
        self.anchorScreenPoint = anchorScreenPoint
    }

    @discardableResult
    private func executeCommand(_ command: String) -> Bool {
        guard canPerformTargetBoundCommand else { return false }
        store.send(.view(.executeCommand(command, source: .contextMenu)))
        return true
    }

    private var displayEntries: [EntryModel] {
        store.state.isCollectionMode
            ? store.state.displayOrderItems
            : (store.state.hierarchyProjectionIsActive
                ? store.state.visibleSelectableEntries(isNormalDirectoryPage: true)
                : store.state.entries)
    }

    private var canPerformTargetBoundCommand: Bool {
        target.isCurrent(
            displayEntries: displayEntries,
            selectedIds: store.state.selectedIds,
        )
            && (!store.state.entryOperations.isLoading || store.state.isCollectionMode)
            && !target.containsBusyEntry(
                busyEntryPaths: Set(store.state.entryOperations.itemStates.filter(\.value.isBusy).map(\.key)),
            )
    }

    private var canPaste: Bool {
        (!store.state.entryOperations.isLoading || store.state.isCollectionMode)
            && !store.state.entryOperations.clipboardItems.isEmpty
    }

    private var canSelectAll: Bool {
        (!store.state.entryOperations.isLoading || store.state.isCollectionMode)
            && !store.state.entries.isEmpty
    }

    @discardableResult
    func observeOpenWithMenu(_ menu: NSMenu) -> NSMenu {
        guard let openWithMenu = menu.item(withTitle: "Open With")?.submenu else { return menu }
        let selectedFiles = target.entries.filter { !$0.isFolder }
        guard !selectedFiles.isEmpty else { return menu }

        openWithObservation?.cancel()
        openWithObservation = observe { [weak self, weak openWithMenu] in
            guard let self, let openWithMenu else { return }
            let applications: [ApplicationInfo] = if selectedFiles.count > 1 {
                store.state.entryOperations.commonApplicationsForSelectedFiles
            } else if let file = selectedFiles.first {
                store.state.entryOperations.applicationsForTypes[Self.typeID(for: file)] ?? []
            } else {
                []
            }
            let isLoading = selectedFiles.contains { file in
                let typeID = Self.typeID(for: file)
                return store.state.entryOperations.openWithInFlightTypeIDs.contains(typeID)
                    || store.state.entryOperations.applicationsForTypes[typeID] == nil
            }
            EntryContextMenuBuilder.updateOpenWithMenu(
                openWithMenu,
                applications: applications,
                isLoading: isLoading,
                target: self,
            )
        }
        return menu
    }

    private static func typeID(for file: EntryModel) -> String {
        UTType(filenameExtension: file.fileExtension)?.identifier ?? UTType.data.identifier
    }

    @objc
    func contextMenuOpenSelectedItem() {
        guard canPerformTargetBoundCommand else { return }
        store.send(.view(.saveScrollOffset(.zero, forPath: store.state.currentPath)))
        store.send(.view(.openSelectedItem(source: .contextMenu)))
    }

    @objc
    func contextMenuOpenSelectedItemInNewWindow(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              canPerformTargetBoundCommand,
              target.entries.contains(where: { $0.fullPath == path && $0.isFolder })
        else {
            return
        }
        store.send(.view(.openPathInNewWindow(path)))
    }

    @objc
    func contextMenuOpenInNewTab(_ sender: NSMenuItem) {
        guard let paths = sender.representedObject as? [String],
              !paths.isEmpty,
              canPerformTargetBoundCommand
        else {
            return
        }
        store.send(.view(.openInNewTab(paths)))
    }

    @objc
    func contextMenuQuickLookSelectedItem() {
        executeCommand("navigation.quickLookSelectedItem")
    }

    @objc
    func contextMenuGetInfoForSelectedItems() {
        if target.entries.isEmpty {
            let currentPath = store.state.currentPath
            guard !currentPath.isEmpty,
                  canPerformCurrentPathCommand
            else { return }
            store.send(.view(.executeCommand("navigation.getInfoForPath", source: .contextMenu)))
            return
        }
        executeCommand("navigation.getInfoForSelectedItems")
    }

    private var canPerformCurrentPathCommand: Bool {
        (!store.state.entryOperations.isLoading || store.state.isCollectionMode)
            && !store.state.entryOperations.itemStates[store.state.currentPath, default: .init()].isBusy
    }

    @objc
    func contextMenuShareSelectedItems() {
        executeCommand("navigation.shareSelectedItems")
    }

    @objc
    func contextMenuPerformService(_ sender: NSMenuItem) {
        guard let serviceName = sender.representedObject as? String,
              canPerformTargetBoundCommand
        else {
            return
        }
        store.send(.view(.performService(serviceName: serviceName)))
    }

    @objc
    func contextMenuRevealSelectedItemsInFinder() {
        executeCommand("navigation.revealSelectedItemsInFinder")
    }

    @objc
    func contextMenuCopySelectedItems() {
        executeCommand("clipboard.copySelectedItems")
    }

    @objc
    func contextMenuCopySelectedAbsolutePaths() {
        executeCommand("clipboard.copySelectedAbsolutePaths")
    }

    @objc
    func contextMenuCopySelectedURLs() {
        executeCommand("clipboard.copySelectedURLs")
    }

    @objc
    func contextMenuCutSelectedItems() {
        executeCommand("clipboard.cutSelectedItems")
    }

    @objc
    func contextMenuPasteItems() {
        guard canPaste else { return }
        store.send(.view(.executeCommand("clipboard.pasteItems", source: .contextMenu)))
    }

    @objc
    func contextMenuSelectAll() {
        guard canSelectAll else { return }
        let orderedIds = store.state.hierarchyProjectionIsActive
            ? store.state.visibleSelectableEntryIDs(isNormalDirectoryPage: true)
            : store.state.displayOrderItems.map(\.id)
        store.send(.view(.selectAll(orderedItemIds: orderedIds)))
    }

    @objc
    func contextMenuStartRename() {
        guard canPerformTargetBoundCommand,
              target.entries.count == 1,
              let item = target.entries.first
        else { return }
        store.send(.view(.startRename(item: item, text: item.name)))
    }

    @objc
    func contextMenuDuplicateSelectedItems() {
        executeCommand("clipboard.duplicateSelectedItems")
    }

    @objc
    func contextMenuCreateAliasForSelectedItems() {
        executeCommand("mutation.createAliasForSelectedItems")
    }

    @objc
    func contextMenuCompressSelectedItems() {
        executeCommand("mutation.compressSelectedItems")
    }

    @objc
    func contextMenuExtractSelectedItem() {
        executeCommand("mutation.extractSelectedItem")
    }

    @objc
    func contextMenuMoveSelectedItemsToTrash() {
        executeCommand("mutation.moveSelectedItemsToTrash")
    }

    @objc
    func contextMenuDeleteSelectedItemsImmediately() {
        executeCommand("mutation.deleteSelectedItemsImmediately")
    }

    @objc
    func contextMenuPutBackSelectedItems() {
        executeCommand("mutation.putBackSelectedItems")
    }

    @objc
    func contextMenuEmptyTrash() {
        guard canPerformTargetBoundCommand else { return }
        store.send(.view(.executeCommand("mutation.emptyTrash", source: .contextMenu)))
    }

    @objc
    func contextMenuOpenWithOther() {
        guard canPerformTargetBoundCommand else { return }
        store.send(.view(.openWithApp(bundleID: nil, source: .contextMenu)))
    }

    @objc
    func contextMenuOpenWithApp(_ sender: NSMenuItem) {
        guard canPerformTargetBoundCommand,
              let bundleID = sender.representedObject as? String
        else { return }
        store.send(.view(.openWithApp(bundleID: bundleID, source: .contextMenu)))
    }

    @objc
    func contextMenuToggleTag(_ sender: NSMenuItem) {
        guard canPerformTargetBoundCommand,
              let tagName = sender.representedObject as? String
        else { return }
        store.send(.view(.toggleTag(tagName, source: .contextMenu)))
    }

    func performTagMutation(name: String, mode: TagMutationMode) {
        guard canPerformTargetBoundCommand else { return }
        store.send(.view(.mutateTag(name: name, mode: mode, source: .contextMenu)))
    }

    @objc
    @MainActor
    func contextMenuShowTags(_ sender: NSMenuItem) {
        guard let tagSpecs = sender.representedObject as? [EntryContextMenuTagSpec],
              canPerformTargetBoundCommand
        else {
            return
        }
        pendingTagSpecs = tagSpecs
    }

    func menuDidClose(_: NSMenu) {
        openWithObservation?.cancel()
        openWithObservation = nil
        DispatchQueue.main.async { [weak self] in
            self?.presentPendingTagsPopover()
        }
    }

    @MainActor
    private func presentPendingTagsPopover() {
        guard let tagSpecs = pendingTagSpecs,
              let anchorView,
              let window = anchorView.window,
              let anchorScreenPoint,
              canPerformTargetBoundCommand
        else {
            pendingTagSpecs = nil
            return
        }
        pendingTagSpecs = nil
        let title = target.entries.count == 1
            ? "Assign tags to \"\(target.entries[0].name)\""
            : "Assign tags to \(target.entries.count) items"
        let controller = EntryTagsPopoverViewController(
            title: title,
            tags: tagSpecs,
            onSelect: { [weak self] name, selection in
                guard let self else { return }
                let mode: TagMutationMode = selection == .on ? .remove : .add
                performTagMutation(name: name, mode: mode)
            },
            onClose: { [weak self] in self?.popover?.performClose(nil) },
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        popoverController = controller
        let anchorInWindow = window.convertPoint(fromScreen: anchorScreenPoint)
        let anchorRect = anchorView.convert(
            NSRect(origin: anchorInWindow, size: NSSize(width: 1, height: 1)),
            from: nil,
        )
        popover.show(relativeTo: anchorRect, of: anchorView, preferredEdge: .maxY)
    }

    func popoverDidClose(_: Notification) {
        pendingTagSpecs = nil
        popover = nil
        popoverController = nil
    }
}

extension EntryContextMenuCoordinator {
    nonisolated static func sendWithSelection(
        _ item: EntryModel,
        selectedIds: Set<EntryModel.ID>,
        entryViewLayoutStore: StoreOf<EntryViewLayoutFeature>,
        action: @escaping @MainActor () -> Void,
    ) {
        MainActor.assumeIsolated {
            if !selectedIds.contains(item.id) {
                entryViewLayoutStore.send(.view(.updateSelection(
                    ids: [item.id],
                    lastSelectedId: item.id,
                    rangeAnchorId: item.id,
                    shouldScrollToSelection: false,
                )))
            }
            action()
        }
    }
}

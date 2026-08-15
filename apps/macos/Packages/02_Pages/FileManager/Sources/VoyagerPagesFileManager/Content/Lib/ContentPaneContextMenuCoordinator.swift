import AppKit
import ComposableArchitecture
import Foundation
import VoyagerEntitiesEntry
import VoyagerFeaturesContentPageNavigation
import VoyagerFeaturesEntryArrangements
import VoyagerFeaturesEntryOperations
import VoyagerShared
import VoyagerWidgetsEntryViewLayout

@MainActor
final class ContentPaneContextMenuCoordinator: NSObject {
    private let store: StoreOf<FileManagerContentFeature>

    init(store: StoreOf<FileManagerContentFeature>) {
        self.store = store
    }

    var configuration: ContentPaneContextMenuBuilder.Configuration {
        .init(
            isTrashFolder: isTrashFolder,
            viewLayout: store.state.entryViewLayout.mode,
            sortKey: store.state.entryViewLayout.entryArrangements.sortKey,
            sortOrder: store.state.entryViewLayout.entryArrangements.sortOrder,
            groupKey: store.state.entryViewLayout.entryArrangements.groupKey,
            canPaste: !store.state.entryViewLayout.entryOperations.clipboardItems.isEmpty,
            itemCount: store.state.entryViewLayout.entries.count,
            canPerformEntryCommands: !store.state.entryViewLayout.entryOperations.isLoading
                || store.state.entryViewLayout.isCollectionMode,
        )
    }

    private var isTrashFolder: Bool {
        guard case let .folder(path) = store.state.navigation.navigationState,
              let trashPath = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first?.path
        else {
            return false
        }
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    @objc
    func contextMenuCreateNewFolder() {
        guard configuration.canPerformEntryCommands else { return }
        store.send(
            .entryViewLayout(.entryOperations(
                .edit(.createNewFolder(
                    parentPath: store.state.navigation.currentPath,
                    siblingNames: store.state.entryViewLayout.entries.map(\.name),
                )),
            )),
        )
    }

    @objc
    func contextMenuSetLayout(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let layout = EntryViewLayoutState.Mode(rawValue: rawValue)
        else { return }
        store.send(.view(.changeLayout(layout)))
    }

    @objc
    func contextMenuSetSortKey(_ sender: NSMenuItem) {
        guard configuration.canChangeSort,
              let rawValue = sender.representedObject as? String,
              let key = SortKey(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setSortKey(key))))
    }

    @objc
    func contextMenuSetSortOrder(_ sender: NSMenuItem) {
        guard configuration.canChangeSort,
              let rawValue = sender.representedObject as? String,
              let order = VoyagerShared.SortOrder(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setSortOrder(order))))
    }

    @objc
    func contextMenuSetGroupKey(_ sender: NSMenuItem) {
        guard configuration.canChangeGroup,
              let rawValue = sender.representedObject as? String,
              let key = GroupKey(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setGroupKey(key))))
    }

    @objc
    func contextMenuEmptyTrash() {
        guard configuration.canPerformEntryCommands else { return }
        store.send(
            .entryViewLayout(.entryOperations(
                .trash(.emptyTrash(paths: store.state.entryViewLayout.entries.map(\.fullPath))),
            )),
        )
    }

    @objc
    func contextMenuPaste() {
        guard configuration.canPasteItems else { return }
        store.send(.entryViewLayout(.delegate(.executeCommand("clipboard.pasteItems"))))
    }

    @objc
    func contextMenuSelectAll() {
        guard configuration.canSelectAll else { return }
        store.send(.view(.selectAllEntries))
    }
}

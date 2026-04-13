import AppKit
import ComposableArchitecture
import Foundation

import VoyagerFeaturesEntryOperations
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
        store.send(
            .entryViewLayout(
                .entryOperations(
                    .edit(.createNewFolder(
                        parentPath: store.state.navigation.currentPath,
                        siblingNames: store.state.entryViewLayout.entries.map(\.name),
                    )),
                ),
            ),
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
        guard let rawValue = sender.representedObject as? String,
              let key = SortKey(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setSortKey(key))))
    }

    @objc
    func contextMenuSetSortOrder(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let order = SortOrder(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setSortOrder(order))))
    }

    @objc
    func contextMenuSetGroupKey(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let key = GroupKey(rawValue: rawValue)
        else { return }
        store.send(.entryViewLayout(.entryArrangements(.setGroupKey(key))))
    }

    @objc
    func contextMenuEmptyTrash() {
        store.send(
            .entryViewLayout(
                .entryOperations(
                    .trash(.emptyTrash(paths: store.state.entryViewLayout.entries.map(\.fullPath))),
                ),
            ),
        )
    }
}

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
            sortKey: store.state.entryArrangements.sortKey,
            sortOrder: store.state.entryArrangements.sortOrder,
            groupKey: store.state.entryArrangements.groupKey,
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
            .entryOperations(
                .edit(.createNewFolder(
                    parentPath: store.state.navigation.currentPath,
                    siblingNames: store.state.entryViewLayout.entries.map(\.name),
                )),
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
        store.send(.entryArrangements(.setSortKey(key)))
    }

    @objc
    func contextMenuSetSortOrder(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let order = VoyagerShared.SortOrder(rawValue: rawValue)
        else { return }
        store.send(.entryArrangements(.setSortOrder(order)))
    }

    @objc
    func contextMenuSetGroupKey(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let key = GroupKey(rawValue: rawValue)
        else { return }
        store.send(.entryArrangements(.setGroupKey(key)))
    }

    @objc
    func contextMenuEmptyTrash() {
        store.send(
            .entryOperations(
                .trash(.emptyTrash(paths: store.state.entryViewLayout.entries.map(\.fullPath))),
            ),
        )
    }
}

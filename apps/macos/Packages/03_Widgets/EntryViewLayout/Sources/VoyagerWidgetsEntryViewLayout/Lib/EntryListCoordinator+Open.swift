@preconcurrency import AppKit
import ComposableArchitecture

extension EntryListCoordinator {
    @objc
    func handleDoubleClick() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0 else { return }
        guard let item = tableView.item(atRow: clickedRow) as? OutlineItem else { return }
        guard case let .entry(entry) = item.kind else { return }
        EntryContextMenuCoordinator.sendWithSelection(
            entry,
            selectedIds: state.selectedIds,
            entryViewLayoutStore: store,
            action: { [weak self] in
                guard let self else { return }
                saveScrollPosition()
                store.send(.view(.openSelectedItem(source: .fileManagerContent)))
            },
        )
    }
}

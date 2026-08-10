@preconcurrency import AppKit

extension EntryListCoordinator {
    func updateListMetricsIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.listIconSize != snapshot.listIconSize || previous.listTextSize != snapshot.listTextSize else {
            return
        }

        if tableView.numberOfRows > 0 {
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0 ..< tableView.numberOfRows))
        }
        reloadTablePreservingScrollAnchor {
            tableView.reloadData()
        }
        syncListRenamingFromStore()
        requestThumbnailsForVisibleRows()
    }

    func syncThumbnailProjectionIfNeeded(previous: RenderSnapshot, snapshot: RenderSnapshot) {
        guard previous.outlineProjectionRevision != snapshot.outlineProjectionRevision else { return }
        refreshThumbnailProjectionForVisibleRows()
    }
}

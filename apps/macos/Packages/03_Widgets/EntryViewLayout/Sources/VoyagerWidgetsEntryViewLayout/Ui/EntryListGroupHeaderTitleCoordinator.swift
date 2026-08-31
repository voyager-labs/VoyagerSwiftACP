import AppKit

/// 뷰포트 상단이 속한 그룹을 추적해 Name 컬럼 헤더 제목을 그룹 제목으로 대체한다(Finder 리스트뷰 방식).
@MainActor
final class EntryListGroupHeaderTitleCoordinator {
    private let scrollView: NSScrollView
    private let tableView: NSOutlineView
    nonisolated(unsafe) private var scrollObserver: (any NSObjectProtocol)?

    init(scrollView: NSScrollView, tableView: NSOutlineView) {
        self.scrollView = scrollView
        self.tableView = tableView
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    func update() {
        setHeaderTitle(activeGroupTitle())
    }

    private func activeGroupTitle() -> String? {
        let visible = scrollView.contentView.documentVisibleRect
        guard tableView.numberOfRows > 0, visible.height > 0 else { return nil }

        var candidateRow = tableView.row(at: NSPoint(x: visible.midX, y: visible.origin.y + 1))
        if candidateRow < 0 {
            candidateRow = tableView.numberOfRows - 1
        }
        var groupRow = candidateRow
        while groupRow >= 0, !isGroupRow(groupRow) {
            groupRow -= 1
        }
        guard groupRow >= 0,
              tableView.rect(ofRow: groupRow).minY < visible.origin.y,
              let item = tableView.item(atRow: groupRow) as? EntryListOutlineItem,
              case let .group(title, _, _) = item.kind
        else {
            return nil
        }
        return title
    }

    private func setHeaderTitle(_ title: String?) {
        guard let column = currentNameColumn() else { return }
        let target = title ?? EntryListColumn.name.title
        if column.title != target {
            column.title = target
            tableView.headerView?.needsDisplay = true
        }
    }

    private func currentNameColumn() -> NSTableColumn? {
        let identifier = NSUserInterfaceItemIdentifier(EntryListColumn.name.rawValue)
        if let column = tableView.tableColumns.first(where: { $0.identifier == identifier }) {
            return column
        }
        return tableView.outlineTableColumn
    }

    private func isGroupRow(_ row: Int) -> Bool {
        guard row >= 0, row < tableView.numberOfRows,
              let item = tableView.item(atRow: row) as? EntryListOutlineItem
        else { return false }
        if case .group = item.kind {
            return true
        }
        return false
    }
}

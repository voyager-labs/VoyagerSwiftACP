import AppKit
import ComposableArchitecture

extension EntryListTableViewController: NSTableViewDelegate {
    func tableView(_: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        guard let tableColumn else { return false }
        guard tableColumn.identifier.rawValue == Column.name.rawValue else { return false }
        guard row >= 0, row < rows.count else { return false }
        guard case let .entry(entry) = rows[row].kind else { return false }
        guard store.state.entries.renamingItemId == entry.id else { return false }
        return true
    }

    func tableView(
        _: NSTableView,
        draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint,
        forRowsWith rowIndexes: IndexSet,
    ) {
        let paths = rowIndexes.compactMap { index -> String? in
            guard index >= 0, index < rows.count else { return nil }
            guard case let .entry(entry) = rows[index].kind else { return nil }
            return entry.fullPath
        }
        guard !paths.isEmpty else { return }
        fsStore.send(.startDrag(paths: paths))
    }

    func tableView(
        _: NSTableView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint,
        operation: NSDragOperation,
    ) {
        guard operation.isEmpty else { return }
        fsStore.send(.startDrag(paths: []))
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard !isUpdatingSortFromStore else { return }
        guard let descriptor = tableView.sortDescriptors.first else { return }
        guard let key = descriptor.key else { return }
        guard let column = Column(rawValue: key) else { return }

        let sortKey: SortKey = switch column {
        case .name:
            .name
        case .dateModified:
            .dateModified
        case .size:
            .size
        case .kind:
            .kind
        }
        let sortOrder: SortOrder = descriptor.ascending ? .ascending : .descending

        if store.state.sortKey != sortKey {
            store.send(.changeSortKey(sortKey))
        }
        if store.state.sortOrder != sortOrder {
            store.send(.changeSortOrder(sortOrder))
        }
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        if case .groupHeader = rows[row].kind {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        if case .groupHeader = rows[row].kind {
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else { return tableView.rowHeight }

        switch rows[row].kind {
        case .groupHeader:
            return 32
        case .entry:
            return max(24, store.state.listIconSize + 4)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else { return nil }

        let columnId = tableColumn?.identifier.rawValue ?? "unknown"
        let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(columnId)")
        let view = makeCellView(tableView: tableView, identifier: cellIdentifier)

        switch rows[row].kind {
        case let .groupHeader(title, colorCode):
            configureGroupHeaderCell(view, title: title, colorCode: colorCode)
            return view
        case let .entry(entry):
            configureEntryCell(view, entry: entry, columnId: columnId)
            return view
        }
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isUpdatingSelectionFromStore else { return }

        let selectedIndexes = tableView.selectedRowIndexes
        let selectedIds: Set<String> = Set(selectedIndexes.compactMap { index in
            guard index >= 0, index < rows.count else { return nil }
            guard case let .entry(entry) = rows[index].kind else { return nil }
            return entry.id
        })

        let clickedRow = tableView.clickedRow
        let lastSelectedId: String? = if selectedIndexes.contains(clickedRow),
                                         clickedRow >= 0,
                                         clickedRow < rows.count,
                                         case let .entry(entry) = rows[clickedRow].kind
        {
            entry.id
        } else if let lastIndex = selectedIndexes.last,
                  lastIndex >= 0,
                  lastIndex < rows.count,
                  case let .entry(entry) = rows[lastIndex].kind
        {
            entry.id
        } else {
            nil
        }

        fsStore.send(.setSelectedIds(ids: selectedIds, lastSelectedId: lastSelectedId))
    }
}

private extension EntryListTableViewController {
    func makeCellView(
        tableView: NSTableView,
        identifier: NSUserInterfaceItemIdentifier,
    ) -> NSTableCellView {
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        view.identifier = identifier
        return view
    }

    @discardableResult
    func setText(
        _ text: String,
        in view: NSTableCellView,
        font: NSFont = .systemFont(ofSize: 12),
    ) -> NSTextField {
        let label = view.textField ?? {
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            view.textField = textField
            return textField
        }()
        label.font = font
        label.stringValue = text
        return label
    }

    func configureGroupHeaderCell(_ view: NSTableCellView, title: String, colorCode: Int?) {
        let prefix = colorCode != nil ? "● " : ""
        setText(prefix + title, in: view, font: .systemFont(ofSize: 12, weight: .semibold))
    }

    func configureEntryCell(_ view: NSTableCellView, entry: Entry, columnId: String) {
        switch Column(rawValue: columnId) {
        case .name:
            let isRenaming = store.state.entries.renamingItemId == entry.id
            let nameText = isRenaming ? store.state.entries.renamingText : entry.name
            let textField = setText(nameText, in: view, font: .systemFont(ofSize: store.state.listTextSize))
            textField.lineBreakMode = .byTruncatingMiddle
            textField.usesSingleLineMode = true

            textField.isEditable = isRenaming
            textField.isSelectable = isRenaming
            textField.isBordered = isRenaming
            textField.drawsBackground = isRenaming
            textField.backgroundColor = isRenaming ? .textBackgroundColor : .clear
            textField.focusRingType = isRenaming ? .default : .none
            textField.delegate = isRenaming ? self : nil

        case .dateModified:
            setText(
                entry.formattedModifiedDate,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)),
            )

        case .size:
            setText(
                entry.formattedSize,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)),
            )

        case .kind:
            let kindText = entry.fileExtension.lowercased() == "voycoll" ? "Voyager Collection" : entry.kind
            setText(
                kindText,
                in: view,
                font: .systemFont(ofSize: max(10, store.state.listTextSize - 1)),
            )

        case .none:
            setText("", in: view)
        }
    }
}

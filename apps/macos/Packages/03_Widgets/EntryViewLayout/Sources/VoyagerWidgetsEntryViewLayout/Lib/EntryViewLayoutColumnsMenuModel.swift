import Foundation

struct EntryViewLayoutColumnsMenuModel: Equatable {
    let toggleItems: [ToggleItem]
    let resetItem: ResetItem

    struct ToggleItem: Equatable {
        let column: EntryListColumn
        let title: String
        let isChecked: Bool
        let isEnabled: Bool
    }

    struct ResetItem: Equatable {
        let title: String
        let isEnabled: Bool
    }

    init(visibleColumns: [EntryListColumn]) {
        let normalizedVisibleColumns = Self.normalizedVisibleColumns(visibleColumns)
        let visibleSet = Set(normalizedVisibleColumns)

        toggleItems = EntryListColumn.allCases.map { column in
            let isRequired = EntryListColumn.requiredColumns.contains(column)
            let isChecked = isRequired || visibleSet.contains(column)
            return ToggleItem(
                column: column,
                title: column.title,
                isChecked: isChecked,
                isEnabled: !isRequired,
            )
        }

        let defaultVisibleColumns = Self.normalizedVisibleColumns(EntryListColumn.defaultVisibleColumns)
        resetItem = ResetItem(
            title: "Reset Columns",
            isEnabled: normalizedVisibleColumns != defaultVisibleColumns,
        )
    }

    private static func normalizedVisibleColumns(_ columns: [EntryListColumn]) -> [EntryListColumn] {
        var normalized: [EntryListColumn] = []
        normalized.reserveCapacity(columns.count)

        for column in columns where !normalized.contains(column) {
            normalized.append(column)
        }

        if normalized.isEmpty {
            normalized = EntryListColumn.defaultVisibleColumns
        }

        for required in EntryListColumn.requiredColumns where !normalized.contains(required) {
            normalized.insert(required, at: 0)
        }

        return normalized
    }
}

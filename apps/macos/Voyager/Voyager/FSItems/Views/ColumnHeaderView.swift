import SwiftUI

struct ColumnHeaderView: View {
    let sortKey: SortKey
    let sortOrder: SortOrder
    let availableWidth: CGFloat
    let onSortKeyChange: (SortKey) -> Void
    let onSortOrderToggle: () -> Void

    private struct ColumnWidths {
        let name: CGFloat
        let date: CGFloat
        let size: CGFloat
        let kind: CGFloat
    }

    private var columnWidths: ColumnWidths {
        let totalPadding = 16.0
        let dividerWidth = 3.0 * 1.0
        let availableForColumns = availableWidth - totalPadding - dividerWidth

        return ColumnWidths(
            name: availableForColumns * 0.4,
            date: availableForColumns * 0.35,
            size: availableForColumns * 0.1,
            kind: availableForColumns * 0.15
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(
                action: {
                    if sortKey == .name {
                        onSortOrderToggle()
                    } else {
                        onSortKeyChange(.name)
                    }
                },
                label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20, height: 1)

                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        if sortKey == .name {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: columnWidths.name, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                }
            )
            .buttonStyle(PlainButtonStyle())

            Divider()
                .frame(height: 20)

            Button(
                action: {
                    if sortKey == .dateModified {
                        onSortOrderToggle()
                    } else {
                        onSortKeyChange(.dateModified)
                    }
                },
                label: {
                    HStack(spacing: 4) {
                        Text("Date Modified")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        if sortKey == .dateModified {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: columnWidths.date, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                }
            )
            .buttonStyle(PlainButtonStyle())

            Divider()
                .frame(height: 20)

            Button(
                action: {
                    if sortKey == .size {
                        onSortOrderToggle()
                    } else {
                        onSortKeyChange(.size)
                    }
                },
                label: {
                    HStack(spacing: 4) {
                        Text("Size")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        if sortKey == .size {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: columnWidths.size, alignment: .trailing)
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
                }
            )
            .buttonStyle(PlainButtonStyle())

            Divider()
                .frame(height: 20)

            Button(
                action: {
                    if sortKey == .kind {
                        onSortOrderToggle()
                    } else {
                        onSortKeyChange(.kind)
                    }
                },
                label: {
                    HStack(spacing: 4) {
                        Text("Kind")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        if sortKey == .kind {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: columnWidths.kind, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                }
            )
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
    }
}

#Preview {
    ColumnHeaderView(
        sortKey: .name,
        sortOrder: .ascending,
        availableWidth: 800,
        onSortKeyChange: { _ in },
        onSortOrderToggle: {}
    )
    .frame(height: 30)
}

import SwiftUI

struct ColumnHeaderView: View {
    let sortKey: SortKey
    let sortOrder: SortOrder
    let availableWidth: CGFloat
    let onSortKeyChange: (SortKey) -> Void
    let onSortOrderToggle: () -> Void

    var body: some View {
        let layout = ListColumnLayout(availableWidth: availableWidth)

        HStack(spacing: layout.columnSpacing) {
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
                            .foregroundColor(sortKey == .name ? .primary : .secondary)

                        if sortKey == .name {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: layout.name, alignment: .leading)
                    .padding(.vertical, 6)
                }
            )
            .buttonStyle(PlainButtonStyle())

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
                            .foregroundColor(sortKey == .dateModified ? .primary : .secondary)

                        if sortKey == .dateModified {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: layout.date, alignment: .leading)
                    .padding(.vertical, 6)
                }
            )
            .buttonStyle(PlainButtonStyle())

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
                            .foregroundColor(sortKey == .size ? .primary : .secondary)

                        if sortKey == .size {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: layout.size, alignment: .trailing)
                    .padding(.vertical, 6)
                }
            )
            .buttonStyle(PlainButtonStyle())

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
                            .foregroundColor(sortKey == .kind ? .primary : .secondary)

                        if sortKey == .kind {
                            Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(width: layout.kind, alignment: .leading)
                    .padding(.vertical, 6)
                }
            )
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, layout.outerPadding)
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

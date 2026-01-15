import AppKit
import SwiftUI

struct ColumnHeaderView: View {
    let sortKey: SortKey
    let sortOrder: SortOrder
    let availableWidth: CGFloat
    let columnWidths: ListColumnWidthsUtils
    let onSortKeyChange: (SortKey) -> Void
    let onSortOrderToggle: () -> Void
    let onColumnResize: (ListColumnWidthsUtils.Column, CGFloat) -> Void

    @State private var activeResizeColumn: ListColumnWidthsUtils.Column?

    var body: some View {
        let layout = columnWidths.makeAbsoluteWidths(
            totalWidth: availableWidth,
            padding: ListColumnLayoutUtils.outerPadding,
            spacing: ListColumnLayoutUtils.columnSpacing,
        )

        HStack(alignment: .top, spacing: 0) {
            columnButton(
                title: "Name",
                width: layout.name,
                sortKey: .name,
                alignment: .leading,
                showIcon: true,
            )

            Spacer().frame(width: layout.columnSpacing)

            columnButtonWithResize(
                title: "Date Modified",
                width: layout.date,
                sortKey: .dateModified,
                alignment: .leading,
                showIcon: false,
                column: .name,
            )

            Spacer().frame(width: layout.columnSpacing)

            columnButtonWithResize(
                title: "Size",
                width: layout.size,
                sortKey: .size,
                alignment: .leading,
                showIcon: false,
                column: .date,
            )

            Spacer().frame(width: layout.columnSpacing)

            columnButtonWithResize(
                title: "Kind",
                width: layout.kind,
                sortKey: .kind,
                alignment: .leading,
                showIcon: false,
                column: .size,
            )
        }
        .padding(.horizontal, layout.outerPadding)
        .frame(height: 28)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom,
        )
        .onChange(of: activeResizeColumn) { newValue in
            if newValue == nil {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func columnButtonContent(
        title: String,
        width: CGFloat,
        sortKey targetSortKey: SortKey,
        alignment: HorizontalAlignment,
        showIcon: Bool,
    ) -> some View {
        HStack(spacing: showIcon ? 8 : 4) {
            if showIcon {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 1)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(sortKey == targetSortKey ? .primary : .secondary)

            if sortKey == targetSortKey {
                Image(systemName: sortOrder == .ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: width, height: 28, alignment: alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private func columnButtonWithResize(
        title: String,
        width: CGFloat,
        sortKey targetSortKey: SortKey,
        alignment: HorizontalAlignment,
        showIcon: Bool,
        column: ListColumnWidthsUtils.Column,
    ) -> some View {
        HStack(alignment: .center, spacing: 2) {
            resizeHandle(column: column)

            Button(
                action: {
                    if sortKey == targetSortKey {
                        onSortOrderToggle()
                    } else {
                        onSortKeyChange(targetSortKey)
                    }
                },
                label: {
                    columnButtonContent(
                        title: title,
                        width: width - 6,
                        sortKey: targetSortKey,
                        alignment: alignment,
                        showIcon: showIcon,
                    )
                },
            )
            .buttonStyle(PlainButtonStyle())
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func columnButton(
        title: String,
        width: CGFloat,
        sortKey targetSortKey: SortKey,
        alignment: HorizontalAlignment,
        showIcon: Bool,
    ) -> some View {
        Button(
            action: {
                if sortKey == targetSortKey {
                    onSortOrderToggle()
                } else {
                    onSortKeyChange(targetSortKey)
                }
            },
            label: {
                columnButtonContent(
                    title: title,
                    width: width,
                    sortKey: targetSortKey,
                    alignment: alignment,
                    showIcon: showIcon,
                )
            },
        )
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func resizeHandle(column: ListColumnWidthsUtils.Column) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 4)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering, activeResizeColumn == nil {
                NSCursor.resizeLeftRight.push()
            } else if !isHovering, activeResizeColumn == nil {
                NSCursor.pop()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if activeResizeColumn == nil {
                        activeResizeColumn = column
                        NSCursor.resizeLeftRight.push()
                    }

                    let delta = value.translation.width
                    onColumnResize(column, delta)
                }
                .onEnded { _ in
                    activeResizeColumn = nil
                    NSCursor.pop()
                },
        )
    }
}

#Preview {
    ColumnHeaderView(
        sortKey: .name,
        sortOrder: .ascending,
        availableWidth: 800,
        columnWidths: .default,
        onSortKeyChange: { _ in },
        onSortOrderToggle: {},
        onColumnResize: { _, _ in },
    )
    .frame(height: 30)
}

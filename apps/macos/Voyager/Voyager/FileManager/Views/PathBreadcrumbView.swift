import SwiftUI

private extension String {
    func width(font: NSFont = .systemFont(ofSize: 12)) -> CGFloat {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes).width
    }
}

private struct ItemPosition {
    let isFirst: Bool
    let isLast: Bool
    let isSecondLast: Bool

    init(index: Int, totalCount: Int) {
        isFirst = (index == 0)
        isLast = (index == totalCount - 1)
        isSecondLast = (totalCount >= 2 && index == totalCount - 2)
    }

    func shouldShowFullName(hasSelectedItem: Bool) -> Bool {
        if hasSelectedItem {
            isFirst || isLast
        } else {
            isFirst || isLast
        }
    }

    func needsFixedSize(hasSelectedItem: Bool) -> Bool {
        shouldShowFullName(hasSelectedItem: hasSelectedItem)
    }
}

private struct BreadcrumbItemView: View {
    let item: BreadcrumbUtils.Item
    let width: CGFloat
    let needsFixedSize: Bool
    let truncationMode: Text.TruncationMode

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: item.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(truncationMode)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: needsFixedSize, vertical: false)
        }
    }
}

private struct BreadcrumbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .white : .secondary)
    }
}

struct PathBreadcrumbView: View {
    let breadcrumbItems: [BreadcrumbUtils.Item]
    let selectedItem: BreadcrumbUtils.Item?
    let availableWidth: CGFloat
    let onNavigate: (String) -> Void

    @State private var hoveredIndex: Int?

    private let iconSize: CGFloat = 14
    private let itemSpacing: CGFloat = 4
    private let chevronSize: CGFloat = 14
    private let minTextWidth: CGFloat = 1

    private func calculateTotalFullWidth() -> CGFloat {
        var total: CGFloat = 0

        for breadcrumb in breadcrumbItems {
            total += iconSize + breadcrumb.name.width()
        }

        if let selected = selectedItem {
            total += iconSize + selected.name.width()
        }

        let chevronCount = breadcrumbItems.count - 1 + (selectedItem != nil ? 1 : 0)
        total += CGFloat(chevronCount) * chevronSize

        let totalElements = breadcrumbItems.count + chevronCount + (selectedItem != nil ? 1 : 0)
        total += CGFloat(totalElements - 1) * itemSpacing

        return total
    }

    private func calculateFixedItemsSpace() -> CGFloat {
        guard let first = breadcrumbItems.first, let last = breadcrumbItems.last else {
            return 0
        }

        var space: CGFloat = 0
        space += iconSize + first.name.width()
        space += iconSize + last.name.width()

        if let selected = selectedItem {
            space += iconSize + selected.name.width()
        }

        let chevronCount = breadcrumbItems.count - 1 + (selectedItem != nil ? 1 : 0)
        space += CGFloat(chevronCount) * chevronSize

        let fixedItemCount = selectedItem != nil ? 2 : 2
        let fixedElementsCount = fixedItemCount + chevronCount
        space += CGFloat(fixedElementsCount - 1) * itemSpacing

        return space
    }

    private func calculateDynamicMaxWidth(for item: BreadcrumbUtils.Item, at index: Int) -> CGFloat {
        guard availableWidth > 0 else {
            return item.name.width()
        }

        let position = ItemPosition(index: index, totalCount: breadcrumbItems.count)
        let itemTextWidth = item.name.width()

        if hoveredIndex == index || position.shouldShowFullName(hasSelectedItem: selectedItem != nil) {
            return itemTextWidth
        }

        if calculateTotalFullWidth() <= availableWidth {
            return itemTextWidth
        }

        let minRequiredCount = selectedItem != nil ? 2 : 2
        guard breadcrumbItems.count > minRequiredCount else {
            return itemTextWidth
        }

        let fixedSpace = calculateFixedItemsSpace()
        let remainingSpace = availableWidth - fixedSpace
        let middleCount = selectedItem != nil ? breadcrumbItems.count - 2 : breadcrumbItems.count - 2

        guard middleCount > 0 else {
            return itemTextWidth
        }

        let budgetPerItem = remainingSpace / CGFloat(middleCount)
        let textBudget = budgetPerItem - iconSize

        return itemTextWidth <= textBudget ? itemTextWidth : max(minTextWidth, textBudget)
    }

    var body: some View {
        HStack(spacing: itemSpacing) {
            if !breadcrumbItems.isEmpty {
                ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                    let position = ItemPosition(index: index, totalCount: breadcrumbItems.count)

                    Button {
                        onNavigate(item.fullPath)
                    } label: {
                        BreadcrumbItemView(
                            item: item,
                            width: calculateDynamicMaxWidth(for: item, at: index),
                            needsFixedSize: position.needsFixedSize(hasSelectedItem: selectedItem != nil),
                            truncationMode: .tail,
                        )
                    }
                    .buttonStyle(BreadcrumbButtonStyle())
                    .help(item.fullPath)
                    .onHover { isHovered in
                        hoveredIndex = isHovered ? index : nil
                    }
                    .contextMenu {
                        Button {
                            AppDelegate.shared?.createNewTab(path: item.fullPath)
                        } label: {
                            Text("Open in New Tab")
                        }

                        Button {
                            let parentPath = URL(fileURLWithPath: item.fullPath).deletingLastPathComponent().path
                            onNavigate(parentPath)
                        } label: {
                            Text("Show in Enclosing Folder")
                        }
                        .disabled(item.fullPath == "/")
                    }

                    if index < breadcrumbItems.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let selectedItem {
                if !breadcrumbItems.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                BreadcrumbItemView(
                    item: selectedItem,
                    width: selectedItem.name.width(),
                    needsFixedSize: true,
                    truncationMode: .middle,
                )
                .foregroundColor(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 20)
    }
}

import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers
import VoyagerEntitiesTag
import VoyagerShared

struct SidebarView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var contentTabHoveredItemID: ContentTabID?

    @State private var fixedLocationHoveredItemID: FileManagerFixedLocationItem.ID?

    @State private var isNewTabHovered = false

    @State private var sidebarEntryDropTarget: FileManagerSidebarEntryDropTarget?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !store.allFixedLocationItems.isEmpty {
                        fixedLocationsGrid
                            .padding(.top, store.fixedLocationItems.isEmpty ? 0 : 50)
                    }

                    if !store.contentTabSidebarItems.isEmpty {
                        contentTabRows(pinnedContentTabSidebarItems)

                        if !pinnedContentTabSidebarItems.isEmpty {
                            contentTabSectionDivider
                        }

                        contentTabRows(unpinnedContentTabSidebarItems)

                        Spacer()
                            .frame(height: 4)

                        newContentTabRow

                        Spacer()
                            .frame(height: 8)
                    }

                    Spacer()
                }
            }
            .clipped()
        }
        .background(Color.clear)
        .navigationSplitViewColumnWidth(ideal: store.sidebarWidth)
    }

    private var pinnedContentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] {
        store.contentTabSidebarItems.filter(\.isPinned)
    }

    private var unpinnedContentTabSidebarItems: [ContentTabProjection.ContentTabSidebarItem] {
        store.contentTabSidebarItems.filter { !$0.isPinned }
    }

    @ViewBuilder private var fixedLocationsGrid: some View {
        if store.fixedLocationItems.isEmpty {
            Color.clear
                .frame(height: fixedLocationGridHeight(for: 1))
                .contentShape(Rectangle())
                .contextMenu { fixedLocationsVisibilityMenu }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
                .padding(.bottom, fixedLocationGridBottomSpacing)
        } else {
            GeometryReader { proxy in
                let metrics = fixedLocationGridMetrics(for: proxy.size.width)

                LazyVGrid(columns: metrics.columns, alignment: .leading, spacing: fixedLocationGridGap) {
                    ForEach(store.fixedLocationItems) { item in
                        let dropTarget = FileManagerSidebarEntryDropTarget.fixedLocation(item.id)
                        FixedLocationButton(
                            item: item,
                            width: metrics.cellWidth,
                            height: fixedLocationCellHeight,
                            isHovered: fixedLocationHoveredItemID == item.id,
                            isDropTarget: sidebarEntryDropTarget == dropTarget,
                            onSelect: {
                                store.send(.delegate(.selectFixedLocation(item.id)))
                            },
                            onHover: { isHovered in
                                fixedLocationHoveredItemID = isHovered ? item.id : nil
                            },
                        )
                        .onDrop(of: [.fileURL], delegate: entryDropDelegate(for: dropTarget))
                    }
                }
                .padding(.horizontal, fixedLocationGridHorizontalPadding)
                .padding(.vertical, fixedLocationGridVerticalPadding)
            }
            .frame(height: fixedLocationGridHeight(for: store.fixedLocationItems.count))
            .padding(.bottom, fixedLocationGridBottomSpacing)
            .contentShape(Rectangle())
            .contextMenu { fixedLocationsVisibilityMenu }
        }
    }

    @ViewBuilder private var fixedLocationsVisibilityMenu: some View {
        if !store.allFixedLocationItems.isEmpty {
            Section("Locations") {
                Button("Show All") {
                    store.send(.view(.setAllFixedLocationVisibility(true)))
                }
                Button("Hide All") {
                    store.send(.view(.setAllFixedLocationVisibility(false)))
                }

                Divider()

                ForEach(store.allFixedLocationItems) { item in
                    Toggle(
                        isOn: Binding(
                            get: { !store.hiddenFixedLocationItemIDs.contains(item.id) },
                            set: { isVisible in
                                store.send(.view(.setFixedLocationVisibility(item.id, isVisible)))
                            },
                        ),
                    ) {
                        Label(item.title, systemImage: normalizedSidebarIconName(item.iconName))
                    }
                }
            }
        }
    }

    private var fixedLocationGridGap: CGFloat {
        8
    }

    private var fixedLocationGridHorizontalPadding: CGFloat {
        12
    }

    private var fixedLocationGridVerticalPadding: CGFloat {
        6
    }

    private var fixedLocationGridBottomSpacing: CGFloat {
        8
    }

    private var fixedLocationCellHeight: CGFloat {
        42
    }

    private var fixedLocationMinimumCellWidth: CGFloat {
        42
    }

    private func fixedLocationGridMetrics(for width: CGFloat) -> FixedLocationGridMetrics {
        let availableWidth = max(0, width - fixedLocationGridHorizontalPadding * 2)
        let columnCount = max(
            1,
            Int((availableWidth + fixedLocationGridGap) / (fixedLocationMinimumCellWidth + fixedLocationGridGap)),
        )
        let totalGapWidth = fixedLocationGridGap * CGFloat(max(0, columnCount - 1))
        let cellWidth = max(
            fixedLocationMinimumCellWidth,
            floor((availableWidth - totalGapWidth) / CGFloat(columnCount)),
        )

        return FixedLocationGridMetrics(
            columns: Array(
                repeating: GridItem(.fixed(cellWidth), spacing: fixedLocationGridGap, alignment: .center),
                count: columnCount,
            ),
            cellWidth: cellWidth,
        )
    }

    private func fixedLocationGridHeight(for itemCount: Int) -> CGFloat {
        let width = max(0, store.sidebarWidth - fixedLocationGridHorizontalPadding * 2)
        let columnCount = max(
            1,
            Int((width + fixedLocationGridGap) / (fixedLocationMinimumCellWidth + fixedLocationGridGap)),
        )
        let rowCount = max(1, Int(ceil(Double(itemCount) / Double(columnCount))))
        return fixedLocationGridVerticalPadding * 2
            + CGFloat(rowCount) * fixedLocationCellHeight
            + CGFloat(max(0, rowCount - 1)) * fixedLocationGridGap
    }

    private var contentTabSectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func contentTabRows(_ items: [ContentTabProjection.ContentTabSidebarItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            contentTabRow(item)

            if index < items.count - 1 {
                Spacer()
                    .frame(height: 4)
            }
        }
    }

    private var newContentTabRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text("New Tab")
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(isNewTabHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : Color.clear),
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { isNewTabHovered = $0 }
        .onTapGesture {
            store.send(.delegate(.openContentTab))
        }
    }

    @ViewBuilder
    private func contentTabRow(_ item: ContentTabProjection.ContentTabSidebarItem) -> some View {
        if let dropTarget = FileManagerSidebarEntryDropDelegate.target(for: item) {
            contentTabSidebarRow(item)
                .onDrop(of: [.fileURL], delegate: entryDropDelegate(for: dropTarget))
        } else {
            contentTabSidebarRow(item)
        }
    }

    private func contentTabSidebarRow(_ item: ContentTabProjection.ContentTabSidebarItem) -> some View {
        ContentTabSidebarRow(
            item: item,
            isHovered: contentTabHoveredItemID == item.id,
            isDropTarget: sidebarEntryDropTarget == .contentTab(item.id),
            onSelect: {
                store.send(.delegate(.selectContentTab(item.id)))
            },
            onDuplicate: { store.send(.delegate(.duplicateContentTab(item.id))) },
            onPin: {
                store.send(.delegate(.pinContentTab(item.id)))
            },
            onUnpin: {
                store.send(.delegate(.unpinContentTab(item.id)))
            },
            onClose: {
                store.send(.delegate(.closeContentTab(item.id)))
            },
            onHover: { isHovered in
                contentTabHoveredItemID = isHovered ? item.id : nil
            },
        )
    }

    private func entryDropDelegate(
        for target: FileManagerSidebarEntryDropTarget,
    ) -> FileManagerSidebarEntryDropDelegate {
        FileManagerSidebarEntryDropDelegate(
            dropTarget: $sidebarEntryDropTarget,
            target: target,
            onDrop: { request in
                store.send(.view(.entryDropRequested(request)))
            },
        )
    }
}

private struct ContentTabSidebarRow: View {
    let item: ContentTabProjection.ContentTabSidebarItem
    let isHovered: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onDuplicate: (() -> Void)?
    let onPin: () -> Void
    let onUnpin: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
            Text(item.title ?? "Untitled")
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipContainer)
                .fill(backgroundColor),
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Duplicate") { onDuplicate?() }
                .accessibilityIdentifier("duplicate-content-tab-\(item.id)")
            if item.isPinned {
                Button("Unpin", action: onUnpin)
            } else {
                Button("Pin", action: onPin)
                Button("Close", action: onClose)
            }
        }
        .overlay(alignment: .trailing) {
            if isHovered {
                SidebarCloseButton(systemName: item.isPinned ? "minus" : "xmark", action: onClose)
                    .padding(.trailing, 14)
            }
        }
        .onTapGesture {
            onSelect()
            keyCommandFocusCoordinator?.requestFocus()
        }
        .onHover(perform: onHover)
    }

    @ViewBuilder private var leadingIcon: some View {
        if let tagColorCode = item.tagColorCode {
            ColorDotView(nsColor: TagColor(colorCode: tagColorCode).nsColor, size: 8)
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            SidebarSymbolIcon(systemName: item.iconName ?? "doc", size: 16, iconSize: 16)
        }
    }

    private var backgroundColor: Color {
        if isDropTarget {
            VoyagerDS.Interaction.hoverFill(for: colorScheme)
        } else if item.isActive {
            VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
        } else if isHovered {
            VoyagerDS.Interaction.hoverFill(for: colorScheme)
        } else {
            Color.clear
        }
    }
}

private func applicationsSidebarIcon() -> NSImage? {
    let appIcon = NSImage(
        contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle"
            + "/Contents/Resources/SidebarApplicationsFolder.icns",
    )
    appIcon?.isTemplate = true
    return appIcon
}

private struct FixedLocationGridMetrics {
    let columns: [GridItem]
    let cellWidth: CGFloat
}

private func normalizedSidebarIconName(_ iconName: String) -> String {
    iconName == "appstore" ? "folder.badge.gearshape" : iconName
}

private struct SidebarSymbolIcon: View {
    let systemName: String
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Group {
            if isApplicationsIcon, let appIcon = applicationsSidebarIcon() {
                Image(nsImage: appIcon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: applicationsIconSize, height: applicationsIconSize)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: normalizedSidebarIconName(systemName))
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(.accentColor)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var applicationsIconSize: CGFloat {
        max(12, iconSize - 2)
    }

    private var isApplicationsIcon: Bool {
        systemName == "appstore" || systemName == "folder.badge.gearshape"
    }
}

private struct FixedLocationButton: View {
    let item: FileManagerFixedLocationItem
    let width: CGFloat
    let height: CGFloat
    let isHovered: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            SidebarSymbolIcon(systemName: item.iconName, size: height, iconSize: 20)
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backgroundColor),
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(isHovered || isDropTarget ? 0.12 : 0.06), lineWidth: 1),
                )
        }
        .buttonStyle(.plain)
        .help(item.accessibilityLabel)
        .accessibilityLabel(item.accessibilityLabel)
        .onHover(perform: onHover)
    }

    private var backgroundColor: Color {
        isHovered || isDropTarget
            ? VoyagerDS.Interaction.hoverFill(for: colorScheme)
            : Color.primary.opacity(0.06)
    }
}

private struct SidebarCloseButton: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? VoyagerDS.Interaction.hoverFill(for: colorScheme) : Color.clear),
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

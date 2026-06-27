import AppKit
import ComposableArchitecture
import SwiftUI
import VoyagerEntitiesTag
import VoyagerShared

struct SidebarView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    @State
    private var contentTabHoveredItemID: ContentTabID?

    @State
    private var isNewTabHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 50)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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

    private func contentTabRow(_ item: ContentTabProjection.ContentTabSidebarItem) -> some View {
        ContentTabSidebarRow(
            item: item,
            isHovered: contentTabHoveredItemID == item.id,
            onSelect: {
                store.send(.delegate(.selectContentTab(item.id)))
            },
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
}

private struct ContentTabSidebarRow: View {
    let item: ContentTabProjection.ContentTabSidebarItem
    let isHovered: Bool
    let onSelect: () -> Void
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
                    .padding(.trailing, 8)
            }
        }
        .onTapGesture {
            onSelect()
            keyCommandFocusCoordinator?.requestFocus()
        }
        .onHover(perform: onHover)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let tagColorCode = item.tagColorCode {
            ColorDotView(nsColor: TagColor(colorCode: tagColorCode).nsColor, size: 8)
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            Image(systemName: item.iconName ?? "doc")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.accentColor)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }

    private var backgroundColor: Color {
        if item.isActive {
            VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
        } else if isHovered {
            VoyagerDS.Interaction.hoverFill(for: colorScheme)
        } else {
            Color.clear
        }
    }
}

private struct SidebarCloseButton: View {
    let systemName: String
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    @State
    private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
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

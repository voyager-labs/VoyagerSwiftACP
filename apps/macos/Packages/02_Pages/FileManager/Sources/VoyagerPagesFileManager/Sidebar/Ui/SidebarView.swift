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
                        SidebarSectionHeader(
                            title: "Tabs",
                            isCollapsed: false,
                            onToggle: {},
                        )

                        ForEach(Array(store.contentTabSidebarItems.enumerated()), id: \.element.id) { index, item in
                            contentTabRow(item)

                            if index < store.contentTabSidebarItems.count - 1 {
                                Spacer()
                                    .frame(height: 4)
                            }
                        }

                        Spacer()
                            .frame(height: 4)

                        newContentTabRow

                        Spacer()
                            .frame(height: 8)
                    }

                    SidebarItemView(
                        iconName: "clock",
                        title: "Recents",
                        isSelected: store.selectedSidebarItem == "Recents",
                        isContextMenuTarget: store.contextMenuTargetId == "Recents",
                        contextMenuTargetWasSelected: store.contextMenuTargetId == "Recents"
                            ? store.contextMenuTargetWasSelected : false,
                        isFavorite: true,
                        iconColor: nil,
                        targetURL: nil,
                        isHovered: false,
                        action: {
                            store.send(.delegate(.showRecents))
                        },
                        onDrop: nil,
                        onContextMenuOpen: nil,
                    )
                    .padding(.top, 8)

                    Spacer()
                        .frame(height: 8)

                    if !store.favorites.isEmpty {
                        SidebarFavoritesSectionView(store: store)
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.locations.isEmpty {
                        SidebarLocationsSectionView(store: store)
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.tags.isEmpty {
                        SidebarTagsSectionView(store: store)
                    }

                    Spacer()
                }
            }
            .clipped()
        }
        .background(Color.clear)
        .onAppear {
            store.send(.internal(.startObservingSystemNotifications))
        }
        .onDisappear {
            store.send(.internal(.stopObservingSystemNotifications))
        }
        .navigationSplitViewColumnWidth(ideal: store.sidebarWidth)
    }

    private var newContentTabRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
                .frame(width: 16)
            Text("New Tab")
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isNewTabHovered ? Color.primary.opacity(0.05) : Color.clear),
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
        if let tagColorCode = item.tagColorCode {
            let isHovered = contentTabHoveredItemID == item.id
            HStack(spacing: 8) {
                ColorDotView(nsColor: TagColor(colorCode: tagColorCode).nsColor, size: 8)
                    .frame(width: 16)
                Text(item.title ?? "Untitled")
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.isActive ? VoyagerDS.Surface
                        .sidebarSelectionBackground(for: colorScheme) :
                        (isHovered ? Color.primary.opacity(0.05) : Color.clear)),
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Close") {
                    store.send(.delegate(.closeContentTab(item.id)))
                }
            }
            .overlay(alignment: .trailing) {
                if isHovered {
                    SidebarCloseButton {
                        store.send(.delegate(.closeContentTab(item.id)))
                    }
                    .padding(.trailing, 8)
                }
            }
            .onTapGesture {
                store.send(.delegate(.selectContentTab(item.id)))
            }
            .onHover { contentTabHoveredItemID = $0 ? item.id : nil }
        } else {
            let isHovered = contentTabHoveredItemID == item.id
            SidebarItemView(
                iconName: item.iconName ?? "doc",
                title: item.title ?? "Untitled",
                isSelected: item.isActive,
                isContextMenuTarget: false,
                contextMenuTargetWasSelected: false,
                isFavorite: false,
                iconColor: item.isPinned ? VoyagerDS.BrandSecondaryColor.c600 : nil,
                targetURL: item.targetURL,
                isHovered: isHovered,
                action: {
                    store.send(.delegate(.selectContentTab(item.id)))
                },
                onDrop: nil,
                onContextMenuOpen: nil,
            )
            .contextMenu {
                Button("Close") {
                    store.send(.delegate(.closeContentTab(item.id)))
                }
            }
            .overlay(alignment: .trailing) {
                if isHovered {
                    SidebarCloseButton {
                        store.send(.delegate(.closeContentTab(item.id)))
                    }
                    .padding(.trailing, 8)
                }
            }
            .onHover { contentTabHoveredItemID = $0 ? item.id : nil }
        }
    }
}

private struct SidebarCloseButton: View {
    let action: () -> Void

    @State
    private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear),
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

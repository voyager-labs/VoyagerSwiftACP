import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct SidebarItemView: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let isFavorite: Bool
    let targetURL: URL?
    let action: () -> Void
    let onDrop: (([NSItemProvider], URL) -> Void)?

    @State private var isDropTarget = false

    @ViewBuilder private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isDropTarget {
            return Color.accentColor
        } else if isSelected {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isDropTarget ? .white : .accentColor)
                .frame(width: 16)
            Text(title)
                .foregroundColor(isDropTarget ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
            restoreFileManagerFocus()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let targetURL = targetURL, let onDrop = onDrop else { return false }
            onDrop(providers, targetURL)
            return true
        }
    }
}

struct TagItemView: View {
    let tag: SidebarUtils.TagItem
    let isSelected: Bool
    let action: () -> Void
    let onDrop: (([NSItemProvider], String) -> Void)? // 태그 드롭 콜백 (providers 전달)

    @State private var isDropTarget = false

    @ViewBuilder private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isDropTarget {
            return Color.accentColor
        } else if isSelected {
            return Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tag.color)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .foregroundColor(isDropTarget ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
            restoreFileManagerFocus()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let onDrop = onDrop else { return false }
            onDrop(providers, tag.name)
            return true
        }
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct SidebarView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        VStack(spacing: 0) {
            Color(nsColor: .controlBackgroundColor)
                .frame(height: 50)
                .ignoresSafeArea(.all, edges: .top)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarItemView(
                        iconName: "clock",
                        title: "Recents",
                        isSelected: store.selectedSidebarItem == "Recents",
                        isFavorite: true,
                        targetURL: nil,
                        action: {
                            store.send(.showRecents)
                        },
                        onDrop: nil
                    )
                    .padding(.top, 8)

                    Spacer()
                        .frame(height: 8)

                    favoritesSection

                    Spacer()
                        .frame(height: 8)

                    locationsSection

                    Spacer()
                        .frame(height: 8)

                    tagsSection

                    Spacer()
                }
            }
            .clipped()
        }
        .frame(minWidth: 150)
        .background(Color(nsColor: NSColor.controlBackgroundColor)) // 시스템 색상 (Container, 인스펙터 패인과 동일)
        .navigationSplitViewColumnWidth(ideal: {
            if let savedWidth = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double,
               savedWidth > 0
            {
                return CGFloat(savedWidth)
            }
            return 200
        }())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.width) { newWidth in
                        store.send(.setSidebarWidth(newWidth))
                    }
            }
        )
    }

    private var favoritesSection: some View {
        Group {
            if !store.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(
                        title: "Favorites",
                        isCollapsed: store.isFavoritesCollapsed,
                        onToggle: {
                            store.send(.toggleFavoritesSection)
                        }
                    )
                    .padding(.top, 8)

                    if !store.isFavoritesCollapsed {
                        ForEach(store.favorites, id: \.url) { favorite in
                            SidebarItemView(
                                iconName: favorite.iconName,
                                title: favorite.name,
                                isSelected: store.selectedSidebarItem == favorite.name,
                                isFavorite: true,
                                targetURL: favorite.url,
                                action: {
                                    store.send(.openFavorite(favorite))
                                },
                                onDrop: { providers, targetURL in
                                    store.send(.dropItemsToSidebarFolder(providers: providers, targetURL: targetURL))
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var locationsSection: some View {
        Group {
            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(
                        title: "Locations",
                        isCollapsed: store.isLocationsCollapsed,
                        onToggle: {
                            store.send(.toggleLocationsSection)
                        }
                    )
                    .padding(.top, 8)

                    if !store.isLocationsCollapsed {
                        ForEach(store.locations, id: \.url) { location in
                            SidebarItemView(
                                iconName: location.iconName,
                                title: location.name,
                                isSelected: store.selectedSidebarItem == location.name,
                                isFavorite: false,
                                targetURL: location.isComputer ? nil : location.url,
                                action: {
                                    if location.isComputer {
                                        store.send(.showComputer)
                                    } else {
                                        store.send(.openLocation(location))
                                    }
                                },
                                onDrop: { providers, targetURL in
                                    store.send(.dropItemsToSidebarFolder(providers: providers, targetURL: targetURL))
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        Group {
            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarSectionHeader(
                        title: "Tags",
                        isCollapsed: store.isTagsCollapsed,
                        onToggle: {
                            store.send(.toggleTagsSection)
                        }
                    )
                    .padding(.top, 8)

                    if !store.isTagsCollapsed {
                        ForEach(store.tags, id: \.name) { tag in
                            TagItemView(
                                tag: tag,
                                isSelected: store.selectedSidebarItem == tag.name,
                                action: {
                                    store.send(.showTag(tag))
                                },
                                onDrop: { providers, tagName in
                                    store.send(.dropItemsToTag(providers: providers, tagName: tagName))
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

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
            Color.accentColor
        } else if isSelected {
            Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        } else {
            Color.clear
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
        .padding(.vertical, 4)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
            restoreFileManagerFocus()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let targetURL, let onDrop else { return false }
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
            Color.accentColor
        } else if isSelected {
            Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        } else {
            Color.clear
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
        .padding(.vertical, 4)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
            restoreFileManagerFocus()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let onDrop else { return false }
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
    @State private var isDark: Bool = isDarkMode()
    @State private var dropTargetIndex: Int?
    @Environment(\.colorScheme)
    var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            sidebarBackgroundColor
                .frame(height: 50)

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
                        onDrop: nil,
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
        .background(sidebarBackgroundColor)
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
            },
        )
        .onAppear {
            isDark = isDarkMode()
        }
        .onChange(of: colorScheme) { newScheme in
            isDark = newScheme == .dark
        }
    }

    private var favoritesSection: some View {
        Group {
            if !store.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSectionHeader(
                        title: "Favorites",
                        isCollapsed: store.isFavoritesCollapsed,
                        onToggle: {
                            store.send(.toggleFavoritesSection)
                        },
                    )
                    .padding(.top, 8)

                    if !store.isFavoritesCollapsed {
                        favoriteDropIndicator(at: 0)

                        ForEach(Array(store.favorites.enumerated()), id: \.element.url) { index, favorite in
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
                                    store.send(.dropItemsToSidebarFolder(
                                        providers: providers,
                                        targetURL: targetURL,
                                    ))
                                },
                            )
                            .contextMenu {
                                Button("Remove from Sidebar") {
                                    store.send(.removeFavorite(favorite))
                                }
                            }

                            favoriteDropIndicator(at: index + 1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteDropIndicator(at index: Int) -> some View {
        let isActive = dropTargetIndex == index

        Rectangle()
            .fill(Color.clear)
            .frame(height: 4)
            .frame(maxWidth: .infinity)
            .overlay(
                Group {
                    if isActive {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                    }
                },
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: Binding(
                get: { dropTargetIndex == index },
                set: { isTargeted in
                    if isTargeted {
                        dropTargetIndex = index
                    } else if dropTargetIndex == index {
                        dropTargetIndex = nil
                    }
                },
            )) { providers in
                handleFavoriteInsert(providers: providers, at: index)
            }
    }

    private func handleFavoriteInsert(providers: [NSItemProvider], at index: Int) -> Bool {
        dropTargetIndex = nil

        var hasProvider = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            hasProvider = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let data = data as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString)
                {
                    Task { @MainActor in
                        store.send(.insertFavorite(url: url, at: index))
                    }
                }
            }
        }
        return hasProvider
    }

    private var locationsSection: some View {
        Group {
            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSectionHeader(
                        title: "Locations",
                        isCollapsed: store.isLocationsCollapsed,
                        onToggle: {
                            store.send(.toggleLocationsSection)
                        },
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
                                },
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
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSectionHeader(
                        title: "Tags",
                        isCollapsed: store.isTagsCollapsed,
                        onToggle: {
                            store.send(.toggleTagsSection)
                        },
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
                                },
                            )
                        }
                    }
                }
            }
        }
    }

    private var sidebarBackgroundColor: Color {
        if isDark {
            Color(nsColor: .controlBackgroundColor)
        } else {
            Color(red: 245 / 255.0, green: 245 / 255.0, blue: 245 / 255.0)
        }
    }
}

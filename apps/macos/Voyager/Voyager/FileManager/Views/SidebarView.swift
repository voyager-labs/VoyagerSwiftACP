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
            return Color.accentColor // Finder 스타일: 진한 파란색
        } else if isSelected {
            // Favorites: 연한 파란색, Locations: 어두운 회색
            return isFavorite ? Color.blue.opacity(0.1) : Color(white: 0.2)
        } else {
            return Color.clear
        }
    }

    private var textColor: Color {
        if isDropTarget {
            return Color.white
        } else if isSelected {
            return isFavorite ? Color.blue : Color.primary
        } else {
            return Color.primary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(textColor)
                .frame(width: 16)
            Text(title)
                .foregroundColor(textColor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
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
            return Color(white: 0.2)
        } else {
            return Color.clear
        }
    }

    private var textColor: Color {
        if isDropTarget {
            return Color.white
        } else if isSelected {
            return tag.color
        } else {
            return Color.primary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tag.color)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .foregroundColor(textColor)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundView)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let onDrop = onDrop else { return false }
            onDrop(providers, tag.name)
            return true
        }
    }
}

struct SidebarView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
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
        .frame(minWidth: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var favoritesSection: some View {
        Group {
            if !store.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Favorites")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

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

    private var locationsSection: some View {
        Group {
            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(store.locations, id: \.url) { location in
                        SidebarItemView(
                            iconName: location.iconName,
                            title: location.name,
                            isSelected: store.selectedSidebarItem == location.name,
                            isFavorite: false,
                            targetURL: location.url,
                            action: {
                                store.send(.openLocation(location))
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

    private var tagsSection: some View {
        Group {
            if !store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

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

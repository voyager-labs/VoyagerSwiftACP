import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let store: StoreOf<FileManagerFeature>
    @Dependency(\.entryClient)
    private var entryClient
    @Dependency(\.userDefaultsClient)
    private var userDefaultsClient
    @State private var dropTargetIndex: Int?
    @State private var draggingFavoriteURL: URL?
    @State private var contextMenuTargetId: String?
    @State private var contextMenuTargetWasSelected = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 50)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FileManagerSidebarItemView(
                        iconName: "clock",
                        title: "Recents",
                        isSelected: store.selectedSidebarItem == "Recents",
                        isContextMenuTarget: contextMenuTargetId == "Recents",
                        contextMenuTargetWasSelected: contextMenuTargetId == "Recents"
                            ? contextMenuTargetWasSelected : false,
                        isFavorite: true,
                        iconColor: nil,
                        targetURL: nil,
                        action: {
                            store.send(.showRecents)
                        },
                        onDrop: nil,
                        onContextMenuOpen: nil,
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
        .background(Color.clear)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            contextMenuTargetId = nil
            contextMenuTargetWasSelected = false
        }
        .navigationSplitViewColumnWidth(ideal: {
            if let savedWidth = userDefaultsClient.object("sidebarWidth") as? Double,
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
    }

    private var favoritesSection: some View {
        Group {
            if !store.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    FileManagerSidebarSectionHeader(
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
                            FileManagerSidebarItemView(
                                iconName: favorite.iconName,
                                title: favorite.displayName,
                                isSelected: store.selectedSidebarItem == favorite.displayName,
                                isContextMenuTarget: contextMenuTargetId == favorite.displayName,
                                contextMenuTargetWasSelected: contextMenuTargetId == favorite.displayName
                                    ? contextMenuTargetWasSelected : false,
                                isFavorite: true,
                                iconColor: favorite.url.pathExtension.lowercased() == "voycoll"
                                    ? VoyagerDS.BrandSecondaryColor.c600
                                    : nil,
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
                                onContextMenuOpen: {
                                    contextMenuTargetId = favorite.displayName
                                    contextMenuTargetWasSelected = store.selectedSidebarItem == favorite.displayName
                                },
                            )
                            .contextMenu {
                                Button("Remove from Sidebar") {
                                    store.send(.removeFavorite(favorite))
                                }
                            }
                            .onDrag {
                                draggingFavoriteURL = favorite.url
                                return NSItemProvider(object: favorite.url as NSURL)
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
            .onDrop(
                of: [UTType.fileURL],
                delegate: FileManagerFavoriteDropDelegate(
                    index: index,
                    dropTargetIndex: $dropTargetIndex,
                    entryClient: entryClient,
                    resolveURL: { providers, completion in
                        resolveFirstDropURL(from: providers, completion: completion)
                    },
                    onDrop: handleFavoriteInsert(providers:at:),
                ),
            )
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
                        let entryClient = entryClient
                        if let existingIndex = store.favorites.firstIndex(where: { $0.url.path == url.path }) {
                            if existingIndex != index {
                                store.send(.reorderFavorites(from: IndexSet(integer: existingIndex), to: index))
                            }
                            draggingFavoriteURL = nil
                            return
                        }
                        var isDirectory: ObjCBool = false
                        guard entryClient.fileExistsAtPath(url.path, &isDirectory),
                              isDirectory.boolValue || url.pathExtension.lowercased() == "voycoll"
                        else {
                            return
                        }
                        store.send(.insertFavorite(url: url, at: index))
                        draggingFavoriteURL = nil
                    }
                }
            }
        }
        return hasProvider
    }

    private func resolveFirstDropURL(
        from providers: [NSItemProvider],
        completion: @escaping @Sendable (URL?) -> Void,
    ) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString)
                else {
                    completion(nil)
                    return
                }
                completion(url)
            }
            return
        }
        completion(nil)
    }

    private var locationsSection: some View {
        Group {
            if !store.locations.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    FileManagerSidebarSectionHeader(
                        title: "Locations",
                        isCollapsed: store.isLocationsCollapsed,
                        onToggle: {
                            store.send(.toggleLocationsSection)
                        },
                    )
                    .padding(.top, 8)

                    if !store.isLocationsCollapsed {
                        ForEach(store.locations, id: \.url) { location in
                            FileManagerSidebarItemView(
                                iconName: location.iconName,
                                title: location.name,
                                isSelected: store.selectedSidebarItem == location.name,
                                isContextMenuTarget: contextMenuTargetId == location.name,
                                contextMenuTargetWasSelected: contextMenuTargetId == location.name
                                    ? contextMenuTargetWasSelected : false,
                                isFavorite: false,
                                iconColor: nil,
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
                                onContextMenuOpen: nil,
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
                    FileManagerSidebarSectionHeader(
                        title: "Tags",
                        isCollapsed: store.isTagsCollapsed,
                        onToggle: {
                            store.send(.toggleTagsSection)
                        },
                    )
                    .padding(.top, 8)

                    if !store.isTagsCollapsed {
                        ForEach(store.tags, id: \.name) { tag in
                            FileManagerTagItemView(
                                tag: tag,
                                isSelected: store.selectedSidebarItem == tag.name,
                                isContextMenuTarget: contextMenuTargetId == tag.name,
                                contextMenuTargetWasSelected: contextMenuTargetId == tag.name
                                    ? contextMenuTargetWasSelected : false,
                                action: {
                                    store.send(.showTag(tag))
                                },
                                onDrop: { providers, tagName in
                                    store.send(.dropItemsToTag(providers: providers, tagName: tagName))
                                },
                                onContextMenuOpen: nil,
                            )
                        }
                    }
                }
            }
        }
    }
}

// swiftlint:enable file_length type_body_length

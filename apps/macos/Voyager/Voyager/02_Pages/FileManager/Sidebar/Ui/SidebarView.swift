import AppKit
import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    let store: StoreOf<FileManagerSidebarFeature>

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 50)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                        action: {
                            store.send(.showRecents)
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
        .frame(minWidth: 150)
        .background(Color.clear)
        .onAppear {
            store.send(.startObservingSystemNotifications)
        }
        .onDisappear {
            store.send(.stopObservingSystemNotifications)
        }
        .navigationSplitViewColumnWidth(ideal: store.sidebarWidth)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.width) { newWidth in
                        store.send(.setSidebarWidth(newWidth))
                    }
            },
        )
    }
}

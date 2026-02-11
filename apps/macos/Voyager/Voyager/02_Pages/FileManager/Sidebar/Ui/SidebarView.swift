import AppKit
import ComposableArchitecture
import SwiftUI

struct SidebarView: View {
    @State private var contextMenuTargetId: String?
    @State private var contextMenuTargetWasSelected = false

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

                    if !store.favorites.isEmpty {
                        SidebarFavoritesSectionView(
                            contextMenuTargetId: $contextMenuTargetId,
                            contextMenuTargetWasSelected: $contextMenuTargetWasSelected,
                            store: store,
                        )
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.locations.isEmpty {
                        SidebarLocationsSectionView(
                            contextMenuTargetId: $contextMenuTargetId,
                            contextMenuTargetWasSelected: $contextMenuTargetWasSelected,
                            store: store,
                        )
                    }

                    Spacer()
                        .frame(height: 8)

                    if !store.tags.isEmpty {
                        SidebarTagsSectionView(
                            contextMenuTargetId: $contextMenuTargetId,
                            contextMenuTargetWasSelected: $contextMenuTargetWasSelected,
                            store: store,
                        )
                    }

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

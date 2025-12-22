import SwiftUI

struct ScopeChipView: View {
    let path: String
    let isDark: Bool
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                // TODO: removeScopeDirectory(path) (voy-95에서 구현)
            } label: {
                Image(systemName: isHovered ? "xmark.circle.fill" : "folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)

            Menu {
                ForEach(favorites, id: \.url) { favorite in
                    Button {
                        // TODO: selectScopeDirectory(favorite.url) (voy-95에서 구현)
                    } label: {
                        HStack {
                            Image(systemName: favorite.iconName)
                                .font(.system(size: 11))
                            Text(favorite.name)
                                .font(.system(size: 12))
                        }
                    }
                }

                if !favorites.isEmpty {
                    Divider()
                }

                // TODO: Favorites 제외 로직은 voy-95에서 구현
                ForEach(Array(backHistory.reversed().prefix(10)), id: \.self) { recentPath in
                    Button {
                        // TODO: selectScopeDirectory(URL(fileURLWithPath: recentPath)) (voy-95에서 구현)
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text(FileManager.default.displayName(atPath: recentPath))
                                .font(.system(size: 12))
                        }
                    }
                }

                if !backHistory.isEmpty {
                    Divider()
                }

                Button {
                    // TODO: NSOpenPanel 열기 (voy-95에서 구현)
                } label: {
                    Text("Other...")
                }
            } label: {
                Text(FileManager.default.displayName(atPath: path))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

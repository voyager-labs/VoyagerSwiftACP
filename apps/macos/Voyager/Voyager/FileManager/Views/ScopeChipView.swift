import ComposableArchitecture
import SwiftUI

struct ScopeChipView: View {
    let paths: [String]
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool
    let favorites: [SidebarUtils.FavoriteItem]
    let backHistory: [String]

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                directoryNameChip(path: path, index: index)
            }

            if !paths.isEmpty {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
        )
    }

    @ViewBuilder
    private func directoryNameChip(path: String, index _: Int) -> some View {
        let displayName = FileManager.default.displayName(atPath: path)

        HStack(spacing: 4) {
            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                store.send(.removeScope(path: path))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(subChipBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(subChipBorderColor, lineWidth: 0.5)
        )
        .onTapGesture {
            // TODO: 콤보박스 열기 구현
        }
    }

    private var subChipBackgroundColor: Color {
        if isDark {
            return Color.white.opacity(0.15)
        } else {
            return Color.black.opacity(0.08)
        }
    }

    private var subChipBorderColor: Color {
        if isDark {
            return Color.white.opacity(0.2)
        } else {
            return Color.black.opacity(0.15)
        }
    }
}

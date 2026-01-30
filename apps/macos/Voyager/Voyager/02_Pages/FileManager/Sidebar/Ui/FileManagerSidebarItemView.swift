import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileManagerSidebarItemView: View {
    let iconName: String
    let title: String
    let isSelected: Bool
    let isContextMenuTarget: Bool
    let contextMenuTargetWasSelected: Bool
    let isFavorite: Bool
    let iconColor: Color?
    let targetURL: URL?
    let action: () -> Void
    let onDrop: (([NSItemProvider], URL) -> Void)?
    let onContextMenuOpen: (() -> Void)?

    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isDropTarget = false

    @ViewBuilder private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isContextMenuTarget ? contextMenuOutlineColor : Color.clear,
                        lineWidth: isContextMenuTarget ? 1 : 0,
                    ),
            )
    }

    private var backgroundColor: Color {
        if isDropTarget {
            Color.accentColor
        } else if isSelected {
            VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
        } else {
            Color.clear
        }
    }

    private var contextMenuOutlineColor: Color {
        Color(nsColor: contextMenuTargetWasSelected ? .secondaryLabelColor : .tertiaryLabelColor)
    }

    private func applicationsIcon() -> NSImage? {
        let appIcon = NSImage(
            contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarApplicationsFolder.icns",
        )
        appIcon?.isTemplate = true
        return appIcon
    }

    var body: some View {
        HStack(spacing: 8) {
            if targetURL?.path == "/Applications",
               let appIcon = applicationsIcon()
            {
                // Applications는 시스템 사이드바 아이콘을 사용
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(isDropTarget ? .white : (iconColor ?? .accentColor))
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: iconName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isDropTarget ? .white : (iconColor ?? .accentColor))
                    .frame(width: 16)
            }
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
        .overlay(
            Group {
                if let onContextMenuOpen {
                    FileManagerRightClickCaptureView(onRightClick: onContextMenuOpen)
                        .allowsHitTesting(false)
                }
            },
        )
    }
}

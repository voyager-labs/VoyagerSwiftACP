import AppKit
import SwiftUI
import UniformTypeIdentifiers

import VoyagerEntitiesTag
import VoyagerShared

struct SidebarTagItemView: View {
    let tag: Tag
    let isSelected: Bool
    let isContextMenuTarget: Bool
    let contextMenuTargetWasSelected: Bool
    let action: () -> Void
    let onDrop: (([NSItemProvider], String) -> Void)? // 태그 드롭 콜백 (providers 전달)
    let onContextMenuOpen: (() -> Void)?

    @Environment(\.colorScheme)
    private var colorScheme

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator
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

    var body: some View {
        HStack(spacing: 8) {
            ColorDotView(nsColor: tag.tagColor.nsColor, size: 8)
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
            keyCommandFocusCoordinator?.requestFocus()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard let onDrop else { return false }
            onDrop(providers, tag.name)
            return true
        }
        .overlay {
            if let onContextMenuOpen {
                SidebarRightClickCaptureView(onRightClick: onContextMenuOpen)
                    .allowsHitTesting(false)
            }
        }
    }
}

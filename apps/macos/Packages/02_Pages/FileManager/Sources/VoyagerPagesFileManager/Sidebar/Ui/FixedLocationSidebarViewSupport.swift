import AppKit
import SwiftUI
import VoyagerEntitiesTag
import VoyagerShared

func normalizedSidebarIconName(_ iconName: String) -> String {
    iconName == "appstore" ? "folder.badge.gearshape" : iconName
}

private func applicationsSidebarIcon() -> NSImage? {
    let appIcon = NSImage(
        contentsOfFile:
        "/System/Library/CoreServices/CoreTypes.bundle"
            + "/Contents/Resources/SidebarApplicationsFolder.icns",
    )
    appIcon?.isTemplate = true
    return appIcon
}

struct SidebarSymbolIcon: View {
    let systemName: String
    let size: CGFloat
    let iconSize: CGFloat
    var foregroundColor: Color = .accentColor

    var body: some View {
        Group {
            if isApplicationsIcon, let appIcon = applicationsSidebarIcon() {
                Image(nsImage: appIcon)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: applicationsIconSize, height: applicationsIconSize)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: normalizedSidebarIconName(systemName))
                    .font(.system(size: iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(foregroundColor)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var applicationsIconSize: CGFloat {
        max(12, iconSize - 2)
    }

    private var isApplicationsIcon: Bool {
        systemName == "appstore" || systemName == "folder.badge.gearshape"
    }
}

struct FixedLocationButton: View {
    let item: FileManagerFixedLocationItem
    let workspaceClient: WorkspaceClient
    let height: CGFloat
    let isHovered: Bool
    let isDropTarget: Bool
    let reorderDragSource: FileManagerTopNavigationReorderDragSourceConfiguration?
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        FixedLocationSidebarButtonHost(
            rootView: AnyView(tilePresentation),
            accessibilityLabel: item.accessibilityLabel,
            isEnabled: true,
            reorderDragSource: reorderDragSource,
            onActivate: onSelect,
        )
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .help("\(item.title)\n\(item.path)")
        .onHover(perform: onHover)
    }

    private var tilePresentation: some View {
        icon
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered || isDropTarget ? 0.12 : 0.06), lineWidth: 1),
            )
    }

    @ViewBuilder private var icon: some View {
        if let finalIcon = workspaceClient.cachedIconForFile(item.path) {
            Image(nsImage: finalIcon)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Image(systemName: item.iconName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(VoyagerDS.SystemColor.tertiaryLabel)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private var backgroundColor: Color {
        isHovered || isDropTarget
            ? VoyagerDS.Interaction.hoverFill(for: colorScheme)
            : Color.primary.opacity(0.06)
    }
}

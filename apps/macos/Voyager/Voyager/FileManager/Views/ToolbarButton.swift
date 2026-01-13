import SwiftUI

struct ToolbarButtonLabel: View {
    enum Metrics {
        static let iconSize = CGFloat(24)
        static let iconFont = Font.system(size: 13, weight: .medium)
        static let hoverCornerRadius = VoyagerDS.Radius.toolbarButton
    }

    let systemName: String
    let isEnabled: Bool
    let font: Font?
    let isHovered: Bool
    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(font ?? Metrics.iconFont)
                .foregroundColor(isEnabled ? .primary : .secondary)
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
            RoundedRectangle(cornerRadius: Metrics.hoverCornerRadius)
                .fill(
                    isEnabled && isHovered
                        ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
                        : .clear,
                )
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        }
        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
    }
}

struct ToolbarHoverButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    @State private var isHovered: Bool = false

    var body: some View {
        ToolbarButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            font: font,
            isHovered: isHovered,
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ToolbarMenuButton<Content: View>: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    let menuID: Int?
    let primaryAction: (() -> Void)?
    let menuContent: () -> Content
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered: Bool = false

    init(
        systemName: String,
        isEnabled: Bool,
        font: Font?,
        menuID: Int? = nil,
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder menuContent: @escaping () -> Content,
    ) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.font = font
        self.menuID = menuID
        self.primaryAction = primaryAction
        self.menuContent = menuContent
    }

    var body: some View {
        menuView()
            .frame(width: ToolbarButtonLabel.Metrics.iconSize, height: ToolbarButtonLabel.Metrics.iconSize)
            .menuIndicator(.hidden)
            .background(
                RoundedRectangle(cornerRadius: ToolbarButtonLabel.Metrics.hoverCornerRadius)
                    .fill(
                        isEnabled && isHovered
                            ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
                            : .clear,
                    )
                    .frame(
                        width: ToolbarButtonLabel.Metrics.iconSize,
                        height: ToolbarButtonLabel.Metrics.iconSize,
                    ),
            )
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
            .id(menuID ?? 0)
            .onHover { hovering in
                if isEnabled {
                    isHovered = hovering
                } else {
                    isHovered = false
                }
            }
    }

    @ViewBuilder
    private func menuView() -> some View {
        if let primaryAction {
            Menu {
                menuContent()
            } label: {
                ToolbarButtonLabel(
                    systemName: systemName,
                    isEnabled: isEnabled,
                    font: font,
                    isHovered: isHovered,
                )
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu {
                menuContent()
            } label: {
                ToolbarButtonLabel(
                    systemName: systemName,
                    isEnabled: isEnabled,
                    font: font,
                    isHovered: isHovered,
                )
            }
        }
    }
}

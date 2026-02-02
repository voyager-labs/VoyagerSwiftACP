import SwiftUI

struct ToolbarButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    let isHovered: Bool

    var body: some View {
        IconButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            isHovered: isHovered,
            style: IconButtonStyle.toolbarWithFont(font ?? IconButtonStyle.toolbar.font),
        )
    }
}

extension ToolbarButtonLabel {
    enum Metrics {
        static let iconFont: Font = IconButtonStyle.toolbar.font
    }
}

struct ToolbarHoverButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?

    var body: some View {
        HoverIconButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            style: IconButtonStyle.toolbarWithFont(font ?? IconButtonStyle.toolbar.font),
        )
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
            .frame(width: IconButtonStyle.toolbar.size, height: IconButtonStyle.toolbar.size)
            .menuIndicator(.hidden)
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

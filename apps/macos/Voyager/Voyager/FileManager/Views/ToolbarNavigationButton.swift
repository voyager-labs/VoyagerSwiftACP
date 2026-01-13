import SwiftUI

struct ToolbarNavigationButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(font)
                .foregroundColor(isEnabled ? .primary : .secondary)
                .frame(width: 24, height: 24)
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                .fill(
                    isEnabled && isHovered
                        ? VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme)
                        : .clear,
                )
                .frame(width: 24, height: 24)
        }
        .frame(width: 24, height: 24)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ToolbarNavigationButtonStyle: ButtonStyle {
    let isEnabled: Bool
    @Environment(\.colorScheme)
    private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                    .fill(
                        isEnabled && configuration.isPressed
                            ? VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme)
                            : .clear,
                    )
                    .frame(width: 20, height: 20),
            )
    }
}

struct ToolbarNavigationMenuButton<Content: View>: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    let menuID: Int?
    let primaryAction: () -> Void
    let menuContent: () -> Content
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered: Bool = false

    init(
        systemName: String,
        isEnabled: Bool,
        font: Font?,
        menuID: Int? = nil,
        primaryAction: @escaping () -> Void,
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
        Menu {
            menuContent()
        } label: {
            ToolbarNavigationButtonLabel(
                systemName: systemName,
                isEnabled: isEnabled,
                font: font,
            )
        } primaryAction: {
            primaryAction()
        }
        .frame(width: 24, height: 24)
        .menuIndicator(.hidden)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                .fill(
                    isEnabled && isHovered
                        ? VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme)
                        : .clear,
                )
                .frame(width: 24, height: 24),
        )
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .id(menuID ?? 0)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

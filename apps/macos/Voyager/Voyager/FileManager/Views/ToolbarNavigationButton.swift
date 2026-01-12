import SwiftUI

struct ToolbarNavigationButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundColor(isEnabled ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                    .fill(
                        isEnabled && isHovered
                            ? VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme)
                            : .clear,
                    ),
            )
            .contentShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton))
            .onHover { hovering in
                isHovered = hovering
            }
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
        ZStack {
            Image(systemName: systemName)
                .font(font)
                .foregroundColor(isEnabled ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton)
                        .fill(
                            isEnabled && isHovered
                                ? VoyagerDS.Interaction.toolbarButtonHoverFill(for: colorScheme)
                                : .clear,
                        ),
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: VoyagerDS.Radius.toolbarButton))
        .overlay(
            Menu {
                menuContent()
            } label: {
                Color.clear
                    .frame(width: 24, height: 24)
            } primaryAction: {
                primaryAction()
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
            .id(menuID ?? 0),
        )
        .overlay(
            HoverTrackingOverlay(
                isHovered: Binding(
                    get: { isHovered },
                    set: { newValue in
                        if isEnabled {
                            isHovered = newValue
                        } else {
                            isHovered = false
                        }
                    },
                ),
            ),
        )
    }
}

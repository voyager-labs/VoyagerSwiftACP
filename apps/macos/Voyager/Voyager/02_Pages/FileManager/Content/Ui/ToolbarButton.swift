import SwiftUI

private struct ToolbarButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?
    let isHovered: Bool

    @Environment(\.colorScheme)
    private var colorScheme

    private var style: IconButtonStyle {
        IconButtonStyle.toolbarWithFont(font ?? IconButtonStyle.toolbar.font)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(isEnabled && isHovered ? style.hoverBackground(colorScheme) : .clear)
                .frame(width: style.size, height: style.size)

            Image(systemName: systemName)
                .font(style.font)
                .foregroundColor(isEnabled ? style.enabledColor : style.disabledColor)
                .frame(width: style.size, height: style.size)
        }
        .frame(width: style.size, height: style.size)
    }
}

struct ToolbarHoverButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let font: Font?

    @State private var isHovered: Bool = false

    init(
        systemName: String,
        isEnabled: Bool,
        font: Font?,
    ) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.font = font
    }

    var body: some View {
        ToolbarButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            font: font,
            isHovered: isHovered,
        )
        .background(HoverTrackingOverlay(isHovered: hoverBinding))
    }

    private var hoverBinding: Binding<Bool> {
        Binding(
            get: { isHovered },
            set: { newValue in
                if isEnabled {
                    isHovered = newValue
                } else {
                    isHovered = false
                }
            },
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

    // Menu is backed by NSMenuButton which swallows SwiftUI .onHover tracking.
    // Use AppKit-level NSTrackingArea instead (HoverTrackingOverlay).
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
        ToolbarButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            font: font,
            isHovered: isHovered,
        )
        .overlay(menuView())
        .overlay(HoverTrackingOverlay(isHovered: hoverBinding))
        .id(menuID ?? 0)
    }

    private var hoverBinding: Binding<Bool> {
        Binding(
            get: { isHovered },
            set: { newValue in
                if isEnabled {
                    isHovered = newValue
                } else {
                    isHovered = false
                }
            },
        )
    }

    @ViewBuilder
    private func menuView() -> some View {
        if let primaryAction {
            Menu {
                menuContent()
            } label: {
                Color.clear
                    .frame(width: IconButtonStyle.toolbar.size, height: IconButtonStyle.toolbar.size)
            } primaryAction: {
                primaryAction()
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
        } else {
            Menu {
                menuContent()
            } label: {
                Color.clear
                    .frame(width: IconButtonStyle.toolbar.size, height: IconButtonStyle.toolbar.size)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
        }
    }
}

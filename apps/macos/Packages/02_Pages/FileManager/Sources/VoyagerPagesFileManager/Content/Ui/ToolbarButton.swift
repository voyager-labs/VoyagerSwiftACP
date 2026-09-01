import AppKit
import SwiftUI
import VoyagerShared

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
                .accessibilityHidden(true)
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
        .background(ToolbarHoverTrackingOverlay(isHovered: hoverBinding))
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

struct ToolbarHoverPillButtonLabel: View {
    let title: String
    let isEnabled: Bool

    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundFill),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered && isEnabled ? 0.14 : 0.10), lineWidth: 1),
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private var backgroundFill: Color {
        guard isEnabled else { return Color.primary.opacity(0.04) }
        if isHovered {
            return VoyagerDS.Interaction.controlHoverFill(for: colorScheme)
        }
        return Color.primary.opacity(0.06)
    }
}

struct ToolbarContextMenuButton: View {
    let systemName: String
    let help: String
    let primaryAction: () -> Void
    let contextMenuTitle: String
    let contextMenuAction: () -> Void
    let contextMenuShortcut: KeyboardShortcut?

    init(
        systemName: String,
        help: String,
        primaryAction: @escaping () -> Void,
        contextMenuTitle: String,
        contextMenuAction: @escaping () -> Void,
        contextMenuShortcut: KeyboardShortcut? = nil,
    ) {
        self.systemName = systemName
        self.help = help
        self.primaryAction = primaryAction
        self.contextMenuTitle = contextMenuTitle
        self.contextMenuAction = contextMenuAction
        self.contextMenuShortcut = contextMenuShortcut
    }

    var body: some View {
        Button(action: primaryAction) {
            ToolbarHoverButtonLabel(
                systemName: systemName,
                isEnabled: true,
                font: nil,
            )
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .contextMenu {
            if let contextMenuShortcut {
                Button(contextMenuTitle, action: contextMenuAction)
                    .keyboardShortcut(contextMenuShortcut)
            } else {
                Button(contextMenuTitle, action: contextMenuAction)
            }
        }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAction(named: Text(contextMenuTitle)) {
            contextMenuAction()
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

    /// Menu is backed by NSMenuButton which swallows SwiftUI .onHover tracking.
    /// Use AppKit-level NSTrackingArea instead.
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
        .overlay(ToolbarHoverTrackingOverlay(isHovered: hoverBinding))
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

private struct ToolbarHoverTrackingOverlay: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = { isHovered = $0 }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onHover = { isHovered = $0 }
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area

            super.updateTrackingAreas()
        }

        override func mouseEntered(with _: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with _: NSEvent) {
            onHover?(false)
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

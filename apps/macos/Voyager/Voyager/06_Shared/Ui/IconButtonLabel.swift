import SwiftUI

struct IconButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let isHovered: Bool
    let style: IconButtonStyle

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(style.font)
                .foregroundColor(isEnabled ? style.enabledColor : style.disabledColor)
                .frame(width: style.size, height: style.size)
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(isEnabled && isHovered ? style.hoverBackground(colorScheme) : .clear)
                .frame(width: style.size, height: style.size)
        }
        .frame(width: style.size, height: style.size)
    }
}

struct HoverIconButtonLabel: View {
    let systemName: String
    let isEnabled: Bool
    let style: IconButtonStyle

    @State private var isHovered: Bool = false

    var body: some View {
        IconButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            isHovered: isHovered,
            style: style,
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct IconButtonStyle {
    let size: CGFloat
    let font: Font
    let cornerRadius: CGFloat
    let enabledColor: Color
    let disabledColor: Color
    let hoverBackground: (ColorScheme) -> Color

    static let toolbar = toolbarWithFont(.system(size: 13, weight: .medium))

    static func toolbarWithFont(_ font: Font) -> IconButtonStyle {
        IconButtonStyle(
            size: 24,
            font: font,
            cornerRadius: VoyagerDS.Radius.toolbarButton,
            enabledColor: .primary,
            disabledColor: .secondary,
            hoverBackground: { scheme in
                VoyagerDS.Surface.sidebarSelectionBackground(for: scheme)
            },
        )
    }

    static let groupToggle = IconButtonStyle(
        size: 16,
        font: .system(size: 11),
        cornerRadius: 4,
        enabledColor: .secondary,
        disabledColor: .secondary,
        hoverBackground: { scheme in
            VoyagerDS.Surface.sidebarSelectionBackground(for: scheme)
        },
    )
}

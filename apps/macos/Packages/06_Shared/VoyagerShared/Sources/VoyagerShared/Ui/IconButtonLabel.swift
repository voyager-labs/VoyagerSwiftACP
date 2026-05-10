import SwiftUI

public struct IconButtonLabel: View {
    public let systemName: String
    public let isEnabled: Bool
    public let isHovered: Bool
    public let style: IconButtonStyle

    @Environment(\.colorScheme)
    private var colorScheme

    public init(systemName: String, isEnabled: Bool, isHovered: Bool, style: IconButtonStyle) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.isHovered = isHovered
        self.style = style
    }

    public var body: some View {
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

public struct HoverIconButtonLabel: View {
    public let systemName: String
    public let isEnabled: Bool
    public let style: IconButtonStyle

    @State private var isHovered: Bool = false

    public init(systemName: String, isEnabled: Bool, style: IconButtonStyle) {
        self.systemName = systemName
        self.isEnabled = isEnabled
        self.style = style
    }

    public var body: some View {
        IconButtonLabel(
            systemName: systemName,
            isEnabled: isEnabled,
            isHovered: isHovered,
            style: style
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

public struct IconButtonStyle: Sendable {
    public let size: CGFloat
    public let font: Font
    public let cornerRadius: CGFloat
    public let enabledColor: Color
    public let disabledColor: Color
    public let hoverBackground: @Sendable (ColorScheme) -> Color

    public init(
        size: CGFloat,
        font: Font,
        cornerRadius: CGFloat,
        enabledColor: Color,
        disabledColor: Color,
        hoverBackground: @escaping @Sendable (ColorScheme) -> Color
    ) {
        self.size = size
        self.font = font
        self.cornerRadius = cornerRadius
        self.enabledColor = enabledColor
        self.disabledColor = disabledColor
        self.hoverBackground = hoverBackground
    }

    public static let toolbar = toolbarWithFont(.system(size: 13, weight: .medium))

    public static func toolbarWithFont(_ font: Font) -> IconButtonStyle {
        IconButtonStyle(
            size: 24,
            font: font,
            cornerRadius: VoyagerDS.Radius.toolbarButton,
            enabledColor: .primary,
            disabledColor: Color(nsColor: .tertiaryLabelColor),
            hoverBackground: { scheme in
                VoyagerDS.Surface.sidebarSelectionBackground(for: scheme)
            }
        )
    }

    public static let groupToggle = IconButtonStyle(
        size: 16,
        font: .system(size: 11),
        cornerRadius: 4,
        enabledColor: Color(nsColor: .tertiaryLabelColor),
        disabledColor: Color(nsColor: .tertiaryLabelColor),
        hoverBackground: { scheme in
            VoyagerDS.Surface.sidebarSelectionBackground(for: scheme)
        }
    )
}

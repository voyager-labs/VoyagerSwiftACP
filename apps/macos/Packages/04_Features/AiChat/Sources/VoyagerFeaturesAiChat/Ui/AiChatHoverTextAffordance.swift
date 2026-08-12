import SwiftUI

struct AiChatHoverTextAffordance: View {
    let title: String
    var titleFontSize: CGFloat = 12
    var titleWeight: Font.Weight = .medium
    var hoverColor: Color = .primary

    @State private var isHovered = false
    @Environment(\.isEnabled)
    private var isEnabled

    private var foregroundColor: Color {
        if !isEnabled { return Color(nsColor: .disabledControlTextColor) }
        return isHovered ? hoverColor : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: titleFontSize, weight: titleWeight))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(foregroundColor)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard isEnabled else {
                isHovered = false
                return
            }
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isEnabled)
    }
}

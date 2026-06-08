import SwiftUI

struct AiChatHoverTextAffordance: View {
    let title: String
    let systemName: String?
    var titleFontSize: CGFloat = 12
    var titleWeight: Font.Weight = .medium
    var hoverColor: Color = .primary

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: titleFontSize, weight: titleWeight))
                .lineLimit(1)
                .truncationMode(.tail)
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isHovered ? hoverColor : .secondary)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .accessibilityHidden(true)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

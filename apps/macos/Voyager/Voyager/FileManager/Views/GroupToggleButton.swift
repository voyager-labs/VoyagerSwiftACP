import SwiftUI

struct GroupToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    @Environment(\.colorScheme)
    private var colorScheme
    @State private var isHovered: Bool = false

    private let buttonSize: CGFloat = 16
    private let cornerRadius: CGFloat = 4

    var body: some View {
        Button(
            action: action,
            label: {
                ZStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: buttonSize, height: buttonSize)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            isHovered
                                ? VoyagerDS.Surface.sidebarSelectionBackground(for: colorScheme)
                                : .clear,
                        )
                        .frame(width: buttonSize, height: buttonSize)
                }
                .frame(width: buttonSize, height: buttonSize)
            },
        )
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

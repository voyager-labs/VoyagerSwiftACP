import SwiftUI

struct GroupToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(
            action: action,
            label: {
                HoverIconButtonLabel(
                    systemName: isCollapsed ? "chevron.right" : "chevron.down",
                    isEnabled: true,
                    style: IconButtonStyle.groupToggle,
                )
            },
        )
        .buttonStyle(.plain)
    }
}

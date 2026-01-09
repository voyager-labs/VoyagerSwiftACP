import SwiftUI

struct StatusBarButton: View {
    let text: String
    let action: () -> Void
    @Environment(\.colorScheme)
    var colorScheme

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(VoyagerDS.Surface.statusButtonBackground(for: colorScheme))
                        .overlay(
                            Capsule()
                                .strokeBorder(VoyagerDS.Surface.statusButtonBorder(for: colorScheme), lineWidth: 1),
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1),
                )
        }
        .buttonStyle(.plain)
    }
}

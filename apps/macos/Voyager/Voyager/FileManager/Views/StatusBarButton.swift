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
                        .fill(statusButtonBackgroundColor)
                        .overlay(
                            Capsule()
                                .strokeBorder(statusButtonBorderColor, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var statusButtonBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(red: 0x37 / 255.0, green: 0x34 / 255.0, blue: 0x30 / 255.0)
        } else {
            return Color(red: 0xFB / 255.0, green: 0xFB / 255.0, blue: 0xFB / 255.0)
        }
    }

    private var statusButtonBorderColor: Color {
        if colorScheme == .dark {
            return Color(red: 0x4D / 255.0, green: 0x49 / 255.0, blue: 0x43 / 255.0)
        } else {
            return Color.black.opacity(0.06)
        }
    }
}

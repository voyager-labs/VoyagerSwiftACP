import SwiftUI

struct LassoRectangleView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 1)
            .background(Color.accentColor.opacity(0.1))
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.05), value: rect)
    }
}

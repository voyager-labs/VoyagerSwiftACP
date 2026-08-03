import SwiftUI

@MainActor
final class SidebarHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

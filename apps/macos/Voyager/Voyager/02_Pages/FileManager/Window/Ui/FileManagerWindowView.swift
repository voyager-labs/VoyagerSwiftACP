import AppKit
import ComposableArchitecture
import SwiftUI

struct FileManagerWindowView: View {
    let store: StoreOf<FileManagerFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        FileManagerWindowViewRepresentable(
            store: store,
            isDark: colorScheme == .dark,
        )
    }
}

private struct FileManagerWindowViewRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    func makeNSViewController(context _: Context) -> FileManagerWindowSplitCoordinator {
        FileManagerWindowSplitCoordinator(
            store: store,
            isDark: isDark,
        )
    }

    func updateNSViewController(
        _ nsViewController: FileManagerWindowSplitCoordinator,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
    }

    static func dismantleNSViewController(
        _ nsViewController: FileManagerWindowSplitCoordinator,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

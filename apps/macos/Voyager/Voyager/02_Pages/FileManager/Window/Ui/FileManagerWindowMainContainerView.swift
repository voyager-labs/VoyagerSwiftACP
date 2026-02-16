import ComposableArchitecture
import SwiftUI

struct FileManagerWindowMainContainerView: View {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    var body: some View {
        FileManagerWindowMainContainerViewRepresentable(
            store: store,
            isDark: isDark,
        )
    }
}

private struct FileManagerWindowMainContainerViewRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    func makeNSViewController(context _: Context) -> FileManagerWindowMainContainerSplitCoordinator {
        FileManagerWindowMainContainerSplitCoordinator(
            store: store,
            isDark: isDark,
        )
    }

    func updateNSViewController(
        _ nsViewController: FileManagerWindowMainContainerSplitCoordinator,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
    }

    static func dismantleNSViewController(
        _ nsViewController: FileManagerWindowMainContainerSplitCoordinator,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

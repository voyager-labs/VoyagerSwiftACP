import ComposableArchitecture
import SwiftUI

struct FileManagerWindowMainContainerView: View {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    var body: some View {
        MainContainerViewControllerRepresentable(
            store: store,
            isDark: isDark,
        )
    }
}

private struct MainContainerViewControllerRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    func makeNSViewController(context _: Context) -> MainContainerSplitCoordinator {
        MainContainerSplitCoordinator(
            store: store,
            isDark: isDark,
        )
    }

    func updateNSViewController(
        _ nsViewController: MainContainerSplitCoordinator,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
    }

    static func dismantleNSViewController(
        _ nsViewController: MainContainerSplitCoordinator,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

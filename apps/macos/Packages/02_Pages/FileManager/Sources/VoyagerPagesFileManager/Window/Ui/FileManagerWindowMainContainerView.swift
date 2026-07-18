import ComposableArchitecture
import SwiftUI

struct FileManagerWindowMainContainerView: View {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool
    let materialOverride: FileManagerWindowMaterialOverride?
    let keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator

    var body: some View {
        MainContainerViewControllerRepresentable(
            store: store,
            isDark: isDark,
            materialOverride: materialOverride,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
        )
    }
}

private struct MainContainerViewControllerRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool
    let materialOverride: FileManagerWindowMaterialOverride?
    let keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator

    func makeNSViewController(context _: Context) -> MainContainerSplitCoordinator {
        MainContainerSplitCoordinator(
            store: store,
            isDark: isDark,
            materialOverride: materialOverride,
            keyCommandFocusCoordinator: keyCommandFocusCoordinator,
        )
    }

    func updateNSViewController(
        _ nsViewController: MainContainerSplitCoordinator,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
        nsViewController.updateMaterialOverride(materialOverride)
    }

    static func dismantleNSViewController(
        _ nsViewController: MainContainerSplitCoordinator,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

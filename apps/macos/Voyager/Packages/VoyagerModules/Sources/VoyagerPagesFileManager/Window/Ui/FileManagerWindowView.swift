import AppKit
import ComposableArchitecture
import SwiftUI

public struct FileManagerWindowView: View {
    public let store: StoreOf<FileManagerFeature>

    @Environment(\.colorScheme)
    private var colorScheme

    public var body: some View {
        FileManagerWindowViewRepresentable(
            store: store,
            isDark: colorScheme == .dark,
        )
    }
}

public struct FileManagerWindowViewRepresentable: NSViewControllerRepresentable {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool

    public func makeNSViewController(context _: Context) -> FileManagerWindowSplitCoordinator {
        FileManagerWindowSplitCoordinator(
            store: store,
            isDark: isDark,
        )
    }

    public func updateNSViewController(
        _ nsViewController: FileManagerWindowSplitCoordinator,
        context _: Context,
    ) {
        nsViewController.updateAppearance(isDark: isDark)
    }

    public static func dismantleNSViewController(
        _ nsViewController: FileManagerWindowSplitCoordinator,
        coordinator _: Void,
    ) {
        nsViewController.tearDown()
    }
}

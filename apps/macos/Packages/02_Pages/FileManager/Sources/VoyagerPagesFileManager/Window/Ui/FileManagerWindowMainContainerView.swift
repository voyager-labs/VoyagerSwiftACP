import ComposableArchitecture
import SwiftUI

struct FileManagerWindowMainContainerView: View {
    let store: StoreOf<FileManagerFeature>
    let isDark: Bool
    let materialOverride: FileManagerWindowMaterialOverride?
    let keyCommandFocusCoordinator: FileManagerKeyCommandFocusCoordinator

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                MainContainerViewControllerRepresentable(
                    store: store,
                    isDark: isDark,
                    materialOverride: materialOverride,
                    keyCommandFocusCoordinator: keyCommandFocusCoordinator,
                )

                if let presentation = store.contentTabSwitcherPresentation {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("file-manager.content-tab-switcher.backdrop")
                        .onTapGesture(perform: dismissContentTabSwitcher)

                    FileManagerContentTabSwitcherView(
                        viewState: ContentTabSwitcherViewState.make(
                            source: presentation.source,
                            contentTabs: store.contentTabs,
                        ),
                        onDismiss: dismissContentTabSwitcher,
                    )
                    .onExitCommand(perform: dismissContentTabSwitcher)
                }
            }
            .alert(
                "Tab Could Not Be Moved",
                isPresented: contentTabMoveFailureIsPresented,
                actions: {
                    Button("OK", action: dismissContentTabMoveFailure)
                },
                message: {
                    Text(contentTabMoveFailureMessage)
                },
            )
        }
    }

    private var contentTabMoveFailureIsPresented: Binding<Bool> {
        Binding(
            get: { store.contentTabMoveFailurePresentation != nil },
            set: { isPresented in
                if !isPresented {
                    dismissContentTabMoveFailure()
                }
            },
        )
    }

    private var contentTabMoveFailureMessage: LocalizedStringKey {
        switch store.contentTabMoveFailurePresentation?.category {
        case .unavailable:
            "The selected window is no longer available."
        case .capacity:
            "The target window cannot accept more tabs."
        case .busy:
            "Finish the current operation before moving this tab."
        case .generic, .none:
            "The tab could not be moved."
        }
    }

    private func dismissContentTabMoveFailure() {
        guard let requestID = store.contentTabMoveFailurePresentation?.requestID else { return }
        store.send(.view(.dismissContentTabMoveFailure(requestID: requestID)))
    }

    private func dismissContentTabSwitcher() {
        store.send(.view(.dismissContentTabSwitcher))
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

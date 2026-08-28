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
                    // backdrop은 제스처 대신 단일 semantic Button으로 해제를 소유한다(포인터 클릭과 AXPress 동일 경로).
                    Button(action: dismissContentTabSwitcher) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss content tab switcher")
                    .accessibilityIdentifier("file-manager.content-tab-switcher.backdrop")

                    FileManagerContentTabSwitcherView(
                        viewState: ContentTabSwitcherViewState.make(
                            source: presentation.source,
                            contentTabs: store.contentTabs,
                            focusedCandidateID: presentation.focusedCandidateID,
                        ),
                        onFocusMove: moveContentTabSwitcherFocus,
                        onActivate: activateContentTabSwitcherCandidate,
                        onDismiss: dismissContentTabSwitcher,
                    )
                }
            }
            .onChange(of: store.contentTabSwitcherPresentation != nil) { isPresented in
                guard !isPresented else { return }
                keyCommandFocusCoordinator.requestFocus()
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

    private func moveContentTabSwitcherFocus(_ direction: ContentTabSwitcherFocusDirection) {
        store.send(.request(.moveContentTabSwitcherFocus(direction: direction)))
    }

    private func activateContentTabSwitcherCandidate(_ id: ContentTabID) {
        store.send(.view(.activateContentTabSwitcherCandidate(id)))
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

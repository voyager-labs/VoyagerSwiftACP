import AppKit
import ComposableArchitecture
import SwiftUI

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>

    @FocusState var isKeyCommandFocused: Bool

    private var mainContent: some View {
        ZStack {
            entryContainerView
            keyCommandOverlay
        }
    }

    @ViewBuilder private var entryContainerView: some View {
        if store.composer.isCollectionSearching {
            loadingView
        } else {
            switch store.viewLayout {
            case .list:
                let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
                EntryListViewRepresentable(store: entryViewLayoutStore, contentStore: store)
            case .grid:
                let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
                EntryGridViewRepresentable(store: entryViewLayoutStore, contentStore: store)
            }
        }
    }

    @ViewBuilder private var keyCommandOverlay: some View {
        KeyCommandView { event in
            handleKeyboardEvent(event)
        }
        .focusable()
        .focused($isKeyCommandFocused)
        .allowsHitTesting(false)
    }

    private var backgroundInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .contextMenu {
                ContentPaneContextMenu(store: store)
            }
            .onTapGesture {
                restoreKeyCommandFocus()
            }
    }

    private var loadingView: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear

                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
        }
    }

    var body: some View {
        mainContent
            .onChange(of: store.entryViewLayout.selectedIds) { _ in
                restoreKeyCommandFocus()
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    restoreKeyCommandFocus()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                store.send(.entryViewLayout(.entryOperations(.appDidBecomeActive)))
            }
            .background(backgroundInteractionLayer)
    }

    private func handleKeyboardEvent(_ event: NSEvent) {
        let command = KeyCommand(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        )
        store.send(.handleKeyCommand(command))
    }

    private func restoreKeyCommandFocus() {
        isKeyCommandFocused = true
        KeyCommandHostingView.restoreCurrentFocus()
    }
}

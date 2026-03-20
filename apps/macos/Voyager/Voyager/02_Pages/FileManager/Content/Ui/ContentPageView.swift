import AppKit
import ComposableArchitecture
import SwiftUI

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>

    @Environment(\.fileManagerKeyCommandFocusCoordinator)
    private var keyCommandFocusCoordinator
    @FocusState var isKeyCommandFocused: Bool

    private var mainContent: some View {
        ZStack {
            entryView
            keyCommandOverlay
        }
    }

    @ViewBuilder private var entryView: some View {
        if store.composer.isCollectionSearching {
            loadingView
        } else {
            switch store.viewLayout {
            case .list:
                let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
                EntryListViewRepresentable(store: entryViewLayoutStore)
            case .grid:
                let entryViewLayoutStore = store.scope(state: \.entryViewLayout, action: \.entryViewLayout)
                EntryGridViewRepresentable(store: entryViewLayoutStore)
            }
        }
    }

    @ViewBuilder private var keyCommandOverlay: some View {
        if store.viewLayout.isGridLayout {
            KeyCommandView(
                onViewCreated: { [weak keyCommandFocusCoordinator] view in
                    keyCommandFocusCoordinator?.register(view)
                },
                onKeyDown: { event in
                    handleKeyboardEvent(event)
                },
            )
            .focusable()
            .focused($isKeyCommandFocused)
            .allowsHitTesting(false)
        }
    }

    private var backgroundInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .contextMenu {
                ContentPaneContextMenu(store: store)
            }
            .onTapGesture {
                guard store.viewLayout.isGridLayout else { return }
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
                guard store.viewLayout.isGridLayout else { return }
                restoreKeyCommandFocus()
            }
            .onAppear {
                store.send(.startObservingSystemNotifications)
                guard store.viewLayout.isGridLayout else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    restoreKeyCommandFocus()
                }
            }
            .onDisappear {
                store.send(.stopObservingSystemNotifications)
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
        keyCommandFocusCoordinator?.requestFocus()
    }
}

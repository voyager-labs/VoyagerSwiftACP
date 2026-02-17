import AppKit
import ComposableArchitecture
import SwiftUI

struct ContentPageView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onNavigate: (String) -> Void

    @FocusState var isKeyCommandFocused: Bool
    static let undoSelector = Selector(("undo:"))
    static let redoSelector = Selector(("redo:"))

    var body: some View {
        mainContent
            .onChange(of: store.entryViewLayout.selectedIds) { _ in
                guard isGridLayout else { return }
                restoreKeyCommandFocus()
            }
            .onChange(of: store.entryViewLayout.isRenaming) { isRenaming in
                guard isGridLayout else { return }
                if !isRenaming {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        restoreKeyCommandFocus()
                    }
                }
            }
            .onAppear {
                guard isGridLayout else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    restoreKeyCommandFocus()
                }
            }
            .background(backgroundInteractionLayer)
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                entryContainerView
                separatorView
                ContentPaneBreadcrumbBarView(
                    store: store,
                    onNavigate: onNavigate,
                )
            }

            keyCommandOverlay
        }
    }

    @ViewBuilder
    private var entryContainerView: some View {
        if isCollectionSearching {
            collectionLoadingView
        } else {
            switch store.viewLayout {
            case .list:
                EntryListViewRepresentable(store: store)
            case .grid:
                EntryGridViewRepresentable(store: store)
            }
        }
    }

    private var separatorView: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    @ViewBuilder
    private var keyCommandOverlay: some View {
        if isGridLayout {
            KeyCommandView { event in
                handleKeyboardEvent(event)
            }
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
                guard isGridLayout else { return }
                restoreKeyCommandFocus()
            }
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

    private var isCollectionSearching: Bool {
        store.composer.isCollectionSearching
    }

    private var isGridLayout: Bool {
        store.viewLayout == .grid
    }

    // TODO: 이름에서 Collection 내용 제외
    private var collectionLoadingView: some View {
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

    private func restoreKeyCommandFocus() {
        isKeyCommandFocused = true
        KeyCommandHostingView.restoreCurrentFocus()
    }
}

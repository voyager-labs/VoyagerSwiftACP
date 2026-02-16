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
        ZStack {
            VStack(spacing: 0) {
                if isCollectionSearching {
                    collectionLoadingView
                } else {
                    switch store.viewLayout {
                    case .list:
                        EntryListView(store: store)
                    case .grid:
                        EntryGridView(store: store)
                    }
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)

                ContentPaneBreadcrumbBarView(
                    store: store,
                    onNavigate: onNavigate,
                )
            }

            if store.viewLayout == .grid {
                KeyCommandView { event in
                    handleKeyboardEvent(event)
                }
                .focusable()
                .focused($isKeyCommandFocused)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: store.entryViewLayout.selectedIds) { _ in
            guard store.viewLayout == .grid else { return }
            restoreKeyCommandFocus()
        }
        .onChange(of: store.entryViewLayout.isRenaming) { isRenaming in
            guard store.viewLayout == .grid else { return }
            if !isRenaming {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    restoreKeyCommandFocus()
                }
            }
        }
        .onAppear {
            guard store.viewLayout == .grid else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                restoreKeyCommandFocus()
            }
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .contextMenu {
                    ContentPaneContextMenu(store: store)
                }
                .onTapGesture {
                    guard store.viewLayout == .grid else { return }
                    restoreKeyCommandFocus()
                },
        )
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

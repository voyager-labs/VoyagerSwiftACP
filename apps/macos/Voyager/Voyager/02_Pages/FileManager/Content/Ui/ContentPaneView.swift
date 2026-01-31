import ComposableArchitecture
import SwiftUI

struct ContentPaneView: View {
    let store: StoreOf<FileManagerFeature>

    @Dependency(\.fileManagerWindowClient)
    var fileManagerWindowClient
    @Dependency(\.entryClient)
    var entryClient
    @Dependency(\.workspaceClient)
    var workspaceClient
    @Dependency(\.fileManagerNavigationClient)
    var navigationClient
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
                        ContentPaneListTableView(store: store)
                    case .grid:
                        ContentPaneGridCollectionView(store: store)
                    }
                }

                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 1)

                breadcrumbStatusBar
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
        .onChange(of: store.entries.selectedIds) { _ in
            guard store.viewLayout == .grid else { return }
            restoreKeyCommandFocus()
        }
        .onChange(of: store.entries.isRenaming) { isRenaming in
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
                .onTapGesture {
                    guard store.viewLayout == .grid else { return }
                    restoreKeyCommandFocus()
                },
        )
    }
}

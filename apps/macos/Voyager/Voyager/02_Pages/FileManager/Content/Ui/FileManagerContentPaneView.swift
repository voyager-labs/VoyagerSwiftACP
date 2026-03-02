import ComposableArchitecture
import SwiftUI

/// 파일 매니저의 Content Pane(툴바/리스트/컴포저 오버레이)를 구성하는 루트 뷰
struct FileManagerContentPaneView: View {
    let store: StoreOf<FileManagerContentFeature>
    let paneState: FileManagerContentPaneViewState
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void
    let onNavigate: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ToolbarView(
                    store: store,
                    onNavigationAction: onNavigationAction,
                )
                ContentPageView(
                    store: store,
                    onNavigate: onNavigate,
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1),
            )

            if paneState.isComposerPresented {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.send(.composer(.setPresented(false))) }
            }

            Group {
                if paneState.isComposerPresented {
                    ComposerView(
                        store: store.scope(state: \.composer, action: \.composer),
                        favorites: paneState.favorites,
                        historyPaths: paneState.historyPaths,
                        isDiscardEnabled: paneState.isDiscardEnabled,
                        canSaveCollection: paneState.canSaveCollection,
                        isTemporaryCollection: paneState.isTemporaryCollection,
                        onDiscardCollectionChanges: {
                            store.send(.collectionDraft(.discardChangesTapped))
                        },
                        onExitComposer: {
                            store.send(.composer(.setPresented(false)))
                        },
                    )
                    .padding(.horizontal, VoyagerDS.Spacing.composerHorizontalPadding)
                    .padding(.top, VoyagerDS.Spacing.composerTopPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(
                .spring(response: 0.25, dampingFraction: 0.75),
                value: paneState.isComposerPresented,
            )
        }
        .background(.thickMaterial)
        .overlay(FileManagerContentMaterialTint())
        .ignoresSafeArea(.all, edges: .top)
    }
}

struct FileManagerContentPaneViewState: Equatable {
    let isComposerPresented: Bool
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
}

private struct FileManagerContentMaterialTint: View {
    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        // 다크 모드에서만 머티리얼 대비를 살리는 얇은 틴트
        if colorScheme == .dark {
            Color.white.opacity(0.06)
                .allowsHitTesting(false)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }
}

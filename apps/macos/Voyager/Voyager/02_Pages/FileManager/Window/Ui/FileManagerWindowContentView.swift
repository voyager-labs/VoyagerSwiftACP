import ComposableArchitecture
import SwiftUI

struct FileManagerWindowContentView: View {
    let store: StoreOf<FileManagerFeature>

    var body: some View {
        WithViewStore(
            store,
            observe: { FileManagerWindowContentViewState(state: $0) },
            content: { viewStore in
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        ToolbarView(store: store)
                        ContentPaneView(store: store)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1),
                    )

                    if viewStore.isComposerPresented {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { store.send(.exitComposer) }
                    }

                    Group {
                        if viewStore.isComposerPresented {
                            ComposerView(
                                store: store.scope(state: \.composer, action: \.composer),
                                favorites: viewStore.favorites,
                                historyPaths: viewStore.historyPaths,
                                isDiscardEnabled: viewStore.isDiscardEnabled,
                                canSaveCollection: viewStore.canSaveCollection,
                                isTemporaryCollection: viewStore.isTemporaryCollection,
                                onDiscardCollectionChanges: { store.send(.discardCollectionChanges) },
                                onExitComposer: { store.send(.exitComposer) },
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
                        value: viewStore.isComposerPresented,
                    )
                }
                .background(.thickMaterial)
                .overlay(FileManagerWindowContentMaterialTint())
                .ignoresSafeArea(.all, edges: .top)
            },
        )
    }
}

private struct FileManagerWindowContentMaterialTint: View {
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

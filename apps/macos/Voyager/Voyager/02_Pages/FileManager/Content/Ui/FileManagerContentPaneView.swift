import ComposableArchitecture
import SwiftUI

import VoyagerFeaturesAiChat

struct FileManagerContentPaneView: View {
    let store: StoreOf<FileManagerContentFeature>
    let chromeProps: FileManagerContentChromeProps
    let overlayProps: FileManagerContentOverlayProps
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void
    let onNavigate: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ToolbarView(
                    store: store,
                    chromeProps: chromeProps,
                    onNavigationAction: onNavigationAction,
                )
                ContentPageView(
                    store: store,
                )
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                ContentPaneBreadcrumbBarView(
                    store: store,
                    chromeProps: chromeProps,
                    onNavigate: onNavigate,
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1),
            )

            if overlayProps.isComposerPresented {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.send(.composer(.setPresented(false))) }
            }

            Group {
                if overlayProps.isComposerPresented {
                    ComposerView(
                        store: store.scope(state: \.composer, action: \.composer),
                        favorites: overlayProps.favorites,
                        historyPaths: overlayProps.historyPaths,
                        isDiscardEnabled: overlayProps.isDiscardEnabled,
                        canSaveCollection: overlayProps.canSaveCollection,
                        isTemporaryCollection: overlayProps.isTemporaryCollection,
                        onDiscardCollectionChanges: {
                            store.send(.delegate(.discardCollectionChanges))
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
                value: overlayProps.isComposerPresented,
            )

            Group {
                if store.isAiChatPresented {
                    HStack {
                        Spacer(minLength: 0)
                        AiChatView(store: store.scope(state: \.aiChat, action: \.aiChat))
                            .padding(.horizontal, VoyagerDS.Spacing.composerHorizontalPadding)
                            .padding(.top, VoyagerDS.Spacing.composerTopPadding)
                            .background(
                                RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                                    .fill(.thickMaterial),
                            )
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(
                .spring(response: 0.25, dampingFraction: 0.75),
                value: store.isAiChatPresented,
            )
        }
        .background(.thickMaterial)
        .overlay(FileManagerContentMaterialTint())
        .ignoresSafeArea(.all, edges: .top)
    }
}

struct FileManagerContentChromeProps: Equatable {
    let computerName: String
    let breadcrumbRoots: FileManagerBreadcrumbRoots
    let pathDisplayNames: [String: String]
    let specialDirectoryIconNames: [String: String]
}

struct FileManagerContentOverlayProps: Equatable {
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

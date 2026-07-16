import ComposableArchitecture
import HotSwiftUI
import SwiftUI
import VoyagerFeaturesAiChat
import VoyagerFeaturesComposer
import VoyagerFeaturesContentPageNavigation
import VoyagerShared

struct FileManagerContentPaneView: View {
    @ObserveInjection private var injection

    let store: StoreOf<FileManagerContentFeature>
    let chromeProps: FileManagerContentChromeProps
    let overlayProps: FileManagerContentOverlayProps
    let activePageAnchor: ContentTabPageAnchor
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void
    let onNavigate: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            contentBody
                .transaction { transaction in
                    transaction.animation = nil
                }
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerDS.Radius.contentPane, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.03), lineWidth: 1)
                        .allowsHitTesting(false),
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
                            store.send(.view(.discardCollectionChanges))
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
        }
        .background(.thickMaterial)
        .overlay(FileManagerContentMaterialTint())
        .ignoresSafeArea(.all, edges: .top)
        .enableInjection()
    }

    private var contentBody: some View {
        VStack(spacing: 0) {
            if activePageAnchor == .homeDefault {
                FileManagerHomePageView(store: store)
            } else if activePageAnchor.isAiChat {
                FileManagerAiChatPageView(
                    store: store,
                    chromeProps: chromeProps,
                    onNavigationAction: onNavigationAction,
                )
            } else {
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
        }
    }
}

struct FileManagerContentChromeProps: Equatable {
    let computerName: String
    let breadcrumbRoots: FileManagerBreadcrumbRoots
    let pathDisplayNames: [String: String]
    let specialDirectoryIconNames: [String: String]
    let isContextualAiChatPresented: Bool
    let activeTabID: ContentTabID?
    let activePageAnchor: ContentTabPageAnchor

    var renderIdentity: String {
        Self.renderIdentity(activeTabID: activeTabID, activePageAnchor: activePageAnchor)
    }

    static func renderIdentity(
        activeTabID: ContentTabID?,
        activePageAnchor: ContentTabPageAnchor,
    ) -> String {
        let tabIdentity = activeTabID?.rawValue ?? "no-active-tab"
        return "\(tabIdentity)::\(activePageAnchor.renderIdentity)"
    }
}

struct FileManagerContentOverlayProps: Equatable {
    let isComposerPresented: Bool
    let favorites: [ScopeFavoriteItem]
    let historyPaths: [String]
    let isDiscardEnabled: Bool
    let canSaveCollection: Bool
    let isTemporaryCollection: Bool
}

extension ContentTabPageAnchor {
    /// AI Chat 페이지 앵커 여부 (연관값 무관)
    var isAiChat: Bool {
        if case .aiChat = self { true } else { false }
    }

    var renderIdentity: String {
        switch self {
        case .homeDefault:
            "home"
        case .directory:
            "directory"
        case .collectionFile, .virtualCollection:
            "collection"
        case .aiChat:
            "aiChat"
        }
    }
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

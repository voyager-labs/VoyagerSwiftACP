import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI

struct ToolbarView: View {
    let store: StoreOf<FileManagerContentFeature>
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void

    private struct CollectionTitleIcon: View {
        var body: some View {
            Image(systemName: "rectangle.stack")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundColor(Color.secondary)
                .accessibilityHidden(true)
        }
    }

    // NOTE: ViewState가 내부에 왜 있는지 체크
    private struct ViewState: Equatable {
        let backHistory: [ContentPageNavigationHistorySnapshot]
        let forwardHistory: [ContentPageNavigationHistorySnapshot]
        let canGoBack: Bool
        let canGoForward: Bool
        let canGoToEnclosingDirectory: Bool
        let currentPath: String
        let isCollectionMode: Bool
        let isOpeningCollectionFile: Bool
        let openedCollectionName: String?
        let openedCollectionURLExists: Bool
        let isOpenedCollectionDirty: Bool
    }

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isTitleAreaHovered: Bool = false

    private var separatorColor: Color {
        Color.primary.opacity(0.12)
    }

    var body: some View {
        WithViewStore(
            store,
            observe: {
                ViewState(
                    backHistory: $0.navigation.backHistory,
                    forwardHistory: $0.navigation.forwardHistory,
                    canGoBack: $0.navigation.canGoBack,
                    canGoForward: $0.navigation.canGoForward,
                    canGoToEnclosingDirectory: $0.navigation.canGoToEnclosingDirectory,
                    currentPath: $0.navigation.currentPath,
                    isCollectionMode: $0.entryViewLayout.entryOperations.loadingContext.isCollectionMode,
                    isOpeningCollectionFile: $0.collectionSession.isOpening,
                    openedCollectionName: $0.collectionSession.openedName,
                    openedCollectionURLExists: $0.collectionSession.openedURL != nil,
                    isOpenedCollectionDirty: $0.isOpenedCollectionDirty,
                )
            },
            content: { viewStore in
                VStack(spacing: 0) {
                    normalModeContent(viewStore: viewStore)
                        .frame(maxHeight: .infinity)
                        .padding(0)
                        .padding(.leading, 0)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 1)
                }
                .background(Color.clear)
            },
        )
    }

    private func normalModeContent(viewStore: ViewStore<ViewState, FileManagerContentFeature.Action>) -> some View {
        HStack(spacing: 0) {
            ToolbarNavigationButtons(
                onNavigationAction: onNavigationAction,
                backHistory: viewStore.backHistory,
                forwardHistory: viewStore.forwardHistory,
                canGoBack: viewStore.canGoBack,
                canGoForward: viewStore.canGoForward,
                canGoToEnclosingDirectory: viewStore.canGoToEnclosingDirectory,
            )

            HStack(spacing: 8) {
                Button(
                    action: { store.send(.composer(.setPresented(true))) },
                    label: {
                        HStack(spacing: 4) {
                            titleContent(viewStore: viewStore)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    },
                )
                .buttonStyle(.borderless)

                if isTitleAreaHovered {
                    ViewToggleButton(store: store)
                    SortGroupButton(store: store)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                isTitleAreaHovered = hovering
            }
            .background(
                Group {
                    if isTitleAreaHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(VoyagerDS.Interaction.toolbarTitleHoverFill(for: colorScheme))
                    }
                },
            )
        }
    }

    private func titleContent(viewStore: ViewStore<ViewState, FileManagerContentFeature.Action>) -> some View {
        let isShowingCollection = viewStore
            .isCollectionMode || (viewStore.isOpeningCollectionFile && viewStore.openedCollectionName != nil)
        let titleText = viewStore.openedCollectionName
            ?? (viewStore.isCollectionMode
                ? "New Collection"
                : FileManager.default.displayName(atPath: viewStore.currentPath))
        let composeSuffix = "/ Compose a filter"
        let showUnsavedIndicator = viewStore.isCollectionMode
            && (!viewStore.openedCollectionURLExists || viewStore.isOpenedCollectionDirty)

        return HStack(spacing: 4) {
            if isShowingCollection {
                CollectionTitleIcon()
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 12))
            }

            Text(titleText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            if showUnsavedIndicator, !isTitleAreaHovered {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(VoyagerDS.BrandSecondaryColor.c600)
            }

            if isTitleAreaHovered {
                Text(composeSuffix)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

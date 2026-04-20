import ComposableArchitecture
import Foundation
import SwiftUI

import VoyagerFeaturesEntryOperations

func showsToolbarRefreshButton(_ collectionStatus: ToolbarCollectionStatusViewState) -> Bool {
    collectionStatus.showsRefreshAffordance
}

func isToolbarRefreshButtonEnabled(_ collectionStatus: ToolbarCollectionStatusViewState) -> Bool {
    collectionStatus.isRefreshEnabled
}

struct ToolbarHistoryItem: Equatable {
    let iconSystemName: String
    let title: String
}

struct ToolbarView: View {
    let store: StoreOf<FileManagerContentFeature>
    let chromeProps: FileManagerContentChromeProps
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
        let backHistoryItems: [ToolbarHistoryItem]
        let forwardHistoryItems: [ToolbarHistoryItem]
        let canGoBack: Bool
        let canGoForward: Bool
        let canGoToEnclosingDirectory: Bool
        let toolbarTitle: String
        let isCollectionMode: Bool
        let isOpeningCollectionFile: Bool
        let openedCollectionName: String?
        let collectionStatus: ToolbarCollectionStatusViewState
    }

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var isTitleAreaHovered: Bool = false

    private var separatorColor: Color {
        Color.primary.opacity(0.12)
    }

    private func displayName(for path: String) -> String {
        if path == "/" {
            return chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName
        }

        if let cached = chromeProps.pathDisplayNames[path], !cached.isEmpty {
            return cached
        }

        let fallback = URL(fileURLWithPath: path).lastPathComponent
        return fallback.isEmpty ? path : fallback
    }

    private func currentNavigationTitle(for navigationState: ContentPageNavigationRoute) -> String {
        switch navigationState {
        case let .folder(path):
            displayName(for: path)
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName
        case let .collection(collectionNavigation):
            switch collectionNavigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }

    private func iconSystemName(forDirectoryPath path: String, homePath: String) -> String {
        if path == "/" {
            return "internaldrive"
        }
        if path == homePath {
            return "house"
        }
        if path.hasPrefix("/Volumes/") {
            return "externaldrive"
        }
        if let mapped = chromeProps.specialDirectoryIconNames[path] {
            return mapped
        }
        return "folder"
    }

    private func historyItem(
        for snapshot: ContentPageNavigationHistorySnapshot,
        homePath: String,
    ) -> ToolbarHistoryItem {
        switch snapshot.navigationState {
        case let .folder(path):
            return ToolbarHistoryItem(
                iconSystemName: iconSystemName(forDirectoryPath: path, homePath: homePath),
                title: displayName(for: path),
            )
        case .recents:
            return ToolbarHistoryItem(iconSystemName: "clock.arrow.circlepath", title: "Recents")
        case let .tags(tagName):
            return ToolbarHistoryItem(iconSystemName: "tag", title: tagName)
        case .computer:
            return ToolbarHistoryItem(
                iconSystemName: "internaldrive",
                title: chromeProps.computerName.isEmpty ? "Computer" : chromeProps.computerName,
            )
        case let .collection(navigation):
            let title: String = switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
            return ToolbarHistoryItem(iconSystemName: "rectangle.stack", title: title)
        }
    }

    var body: some View {
        WithViewStore(
            store,
            observe: { state in
                let homePath = NSHomeDirectory()
                return ViewState(
                    backHistoryItems: state.navigation.backHistory.map { snapshot in
                        historyItem(for: snapshot, homePath: homePath)
                    },
                    forwardHistoryItems: state.navigation.forwardHistory.map { snapshot in
                        historyItem(for: snapshot, homePath: homePath)
                    },
                    canGoBack: state.navigation.canGoBack,
                    canGoForward: state.navigation.canGoForward,
                    canGoToEnclosingDirectory: state.navigation.canGoToEnclosingDirectory,
                    toolbarTitle: currentNavigationTitle(for: state.navigation.navigationState),
                    isCollectionMode: state.isCollectionMode,
                    isOpeningCollectionFile: state.collectionSession.isOpening,
                    openedCollectionName: state.collectionSession.openedName,
                    collectionStatus: .init(
                        isCollectionMode: state.isCollectionMode,
                        openedCollectionURLExists: state.collectionSession.openedURL != nil,
                        isOpenedCollectionDirty: state.isOpenedCollectionDirty,
                        isOpenedCollectionStale: state.isOpenedCollectionStale,
                        canRefreshStaleCollection: state.canRefreshStaleCollection,
                    ),
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
                backHistoryItems: viewStore.backHistoryItems,
                forwardHistoryItems: viewStore.forwardHistoryItems,
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
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    },
                )
                .buttonStyle(.borderless)

                if showsToolbarRefreshButton(viewStore.collectionStatus) {
                    toolbarRefreshButton(viewStore: viewStore)
                }

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
                : viewStore.toolbarTitle)
        let composeSuffix = "/ Compose a filter"
        let showUnsavedIndicator = viewStore.collectionStatus.showsUnsavedIndicator
        let showStaleIndicator = viewStore.collectionStatus.showsStaleIndicator

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

            if showStaleIndicator {
                Text("Stale")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.14)),
                    )
            }

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

    private func toolbarRefreshButton(viewStore: ViewStore<ViewState, FileManagerContentFeature.Action>) -> some View {
        Button(
            action: { store.send(.view(.refreshStaleCollection)) },
            label: {
                ToolbarHoverButtonLabel(
                    systemName: "arrow.clockwise",
                    isEnabled: isToolbarRefreshButtonEnabled(viewStore.collectionStatus),
                    font: .system(size: 11, weight: .semibold),
                )
            },
        )
        .buttonStyle(.borderless)
        .disabled(!isToolbarRefreshButtonEnabled(viewStore.collectionStatus))
    }
}

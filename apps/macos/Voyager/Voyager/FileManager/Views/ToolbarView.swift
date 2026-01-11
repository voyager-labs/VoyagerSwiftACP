import AppKit
import ComposableArchitecture
import SwiftUI

struct ToolbarView: View {
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

    private struct ViewState: Equatable {
        let backHistory: [FileManagerFeature.HistoryEntry]
        let forwardHistory: [FileManagerFeature.HistoryEntry]
        let canGoBack: Bool
        let canGoForward: Bool
        let canGoToEnclosingDirectory: Bool
        let sidebarVisible: Bool
        let currentPath: String
        let isCollectionMode: Bool
        let isOpeningCollectionFile: Bool
        let openedCollectionName: String?
        let openedCollectionURLExists: Bool
        let isOpenedCollectionDirty: Bool
    }

    let store: StoreOf<FileManagerFeature>
    @State private var isTitleAreaHovered: Bool = false
    @State private var isTitleHovered: Bool = false

    var body: some View {
        WithViewStore(
            store,
            observe: {
                ViewState(
                    backHistory: $0.backHistory,
                    forwardHistory: $0.forwardHistory,
                    canGoBack: $0.canGoBack,
                    canGoForward: $0.canGoForward,
                    canGoToEnclosingDirectory: $0.canGoToEnclosingDirectory,
                    sidebarVisible: $0.sidebarVisible,
                    currentPath: $0.currentPath,
                    isCollectionMode: $0.fsItems.isCollectionMode,
                    isOpeningCollectionFile: $0.isOpeningCollectionFile,
                    openedCollectionName: $0.openedCollectionName,
                    openedCollectionURLExists: $0.openedCollectionURL != nil,
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
                        .fill(.ultraThinMaterial)
                        .frame(height: 1)
                }
                .background(Color.clear)
            },
        )
    }

    private func normalModeContent(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        HStack(spacing: 12) {
            backButton(viewStore: viewStore)
            forwardButton(viewStore: viewStore)
            enclosingDirectoryButton(viewStore: viewStore)

            HStack(spacing: 8) {
                titleButton(viewStore: viewStore)

                Spacer()

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
                            .fill(.thickMaterial)
                    }
                },
            )
        }
    }

    private func backButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        ToolbarNavigationMenuButton(
            systemName: "chevron.left",
            isEnabled: viewStore.canGoBack,
            font: nil,
            primaryAction: { store.send(.goBack) },
            menuContent: {
                if viewStore.backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewStore.backHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: { store.send(.goToHistoryIndex(index, isBackHistory: true)) },
                            label: { Text(historyDisplayName(for: entry)) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func forwardButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        ToolbarNavigationMenuButton(
            systemName: "chevron.right",
            isEnabled: viewStore.canGoForward,
            font: nil,
            primaryAction: { store.send(.goForward) },
            menuContent: {
                if viewStore.forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewStore.forwardHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: { store.send(.goToHistoryIndex(index, isBackHistory: false)) },
                            label: { Text(historyDisplayName(for: entry)) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func enclosingDirectoryButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        Button(
            action: { store.send(.goToEnclosingDirectory) },
            label: {
                ToolbarNavigationButtonLabel(
                    systemName: "chevron.up",
                    isEnabled: viewStore.canGoToEnclosingDirectory,
                    font: .system(size: 13, weight: .medium),
                )
            },
        )
        .fixedSize()
        .disabled(!viewStore.canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
    }

    private func titleButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        let isShowingCollection = viewStore
            .isCollectionMode || (viewStore.isOpeningCollectionFile && viewStore.openedCollectionName != nil)
        let titleText = viewStore.openedCollectionName
            ?? (viewStore.isCollectionMode
                ? "New Collection"
                : FileManager.default.displayName(atPath: viewStore.currentPath))
        let isNewCollection = viewStore.isCollectionMode && viewStore.openedCollectionName == nil
        let isDirtySavedCollection = viewStore.isCollectionMode
            && viewStore.openedCollectionURLExists
            && viewStore.isOpenedCollectionDirty
        let suffix = isTitleHovered ? "/ Compose a filter" : "/ Complete saving the filter"

        return Button(
            action: { store.send(.enterComposer) },
            label: {
                HStack(spacing: 4) {
                    if isShowingCollection {
                        CollectionTitleIcon()
                    } else {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                    }

                    Text(titleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    if isNewCollection {
                        Text(suffix)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if isDirtySavedCollection {
                        Text(suffix)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if isTitleHovered {
                        Text("/ Compose a filter")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            },
        )
        .buttonStyle(.borderless)
        .onHover { hovering in
            isTitleHovered = hovering
        }
    }

    private func historyDisplayName(for entry: FileManagerFeature.HistoryEntry) -> String {
        switch entry.navigationState {
        case let .folder(path):
            FileManager.default.displayName(atPath: path)
        case .recents:
            "Recents"
        case let .tags(tagName):
            tagName
        case .computer:
            SidebarUtils.computerName
        case let .collection(navigation):
            switch navigation.kind {
            case .temporary:
                "New Collection"
            case let .file(_, name):
                name
            }
        }
    }
}

import AppKit
import ComposableArchitecture
import SwiftUI

struct ToolbarView: View {
    private struct ViewState: Equatable {
        let backHistory: [FileManagerFeature.HistoryEntry]
        let forwardHistory: [FileManagerFeature.HistoryEntry]
        let canGoBack: Bool
        let canGoForward: Bool
        let canGoToEnclosingDirectory: Bool
        let sidebarVisible: Bool
        let currentPath: String
        let isCollectionMode: Bool
        let openedCollectionName: String?
    }

    let store: StoreOf<FileManagerFeature>
    @State private var isDark: Bool = isDarkMode()
    @State private var isHovered: Bool = false
    @State private var isTitleHovered: Bool = false
    @Environment(\.colorScheme)
    var colorScheme

    private let trafficLightAreaWidth: CGFloat = 80

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
                    openedCollectionName: $0.openedCollectionName,
                )
            },
            content: { viewStore in
                normalModeContent(viewStore: viewStore)
                    .frame(maxHeight: .infinity)
                    .padding(0)
                    .padding(.leading, viewStore.sidebarVisible ? 0 : trafficLightAreaWidth)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(
                        ZStack {
                            toolbarBackgroundColor

                            VStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.black.opacity(0.15))
                                    .frame(height: 1.0)
                            }
                        },
                    )
                    .onHover { hovering in
                        isHovered = hovering
                    }
                    .onAppear {
                        isDark = isDarkMode()
                    }
                    .onChange(of: colorScheme) { newScheme in
                        isDark = newScheme == .dark
                    }
            },
        )
    }

    private func normalModeContent(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        HStack(spacing: 12) {
            backButton(viewStore: viewStore)
            forwardButton(viewStore: viewStore)
            enclosingDirectoryButton(viewStore: viewStore)
            titleButton(viewStore: viewStore)

            Spacer()

            if isHovered {
                ViewToggleButton(store: store)
                SortGroupButton(store: store)
            }
        }
    }

    private func backButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        Menu {
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
        } label: {
            Image(systemName: "chevron.left")
                .foregroundColor(viewStore.canGoBack ? .primary : .secondary)
        } primaryAction: {
            store.send(.goBack)
        }
        .menuIndicator(.hidden)
        .disabled(!viewStore.canGoBack)
        .buttonStyle(.borderless)
    }

    private func forwardButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        Menu {
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
        } label: {
            Image(systemName: "chevron.right")
                .foregroundColor(viewStore.canGoForward ? .primary : .secondary)
        } primaryAction: {
            store.send(.goForward)
        }
        .menuIndicator(.hidden)
        .disabled(!viewStore.canGoForward)
        .buttonStyle(.borderless)
    }

    private func enclosingDirectoryButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        Button(
            action: { store.send(.goToEnclosingDirectory) },
            label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewStore.canGoToEnclosingDirectory ? .primary : .secondary)
            },
        )
        .disabled(!viewStore.canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
    }

    private func titleButton(viewStore: ViewStore<ViewState, FileManagerFeature.Action>) -> some View {
        Button(
            action: { store.send(.enterComposer) },
            label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text(
                        viewStore.openedCollectionName
                            ?? (viewStore.isCollectionMode
                                ? "Temporary Collection"
                                : FileManager.default.displayName(atPath: viewStore.currentPath)),
                    )
                    .font(.system(size: 15, weight: .semibold))

                    if isTitleHovered {
                        Text("/ Compose a filter")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            },
        )
        .buttonStyle(.plain)
        .onHover { hovering in
            isTitleHovered = hovering
        }
    }

    private var toolbarBackgroundColor: Color {
        if isDark {
            Color(red: 0.17, green: 0.17, blue: 0.17)
        } else {
            Color(nsColor: .controlBackgroundColor)
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
                "Temporary Collection"
            case let .file(_, name):
                name
            }
        }
    }
}

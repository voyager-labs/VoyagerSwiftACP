import AppKit
import ComposableArchitecture
import SwiftUI

struct ToolbarView: View {
    let store: StoreOf<FileManagerFeature>
    @State private var isDark: Bool = isDarkMode()
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme)
    var colorScheme

    private let trafficLightAreaWidth: CGFloat = 80

    var body: some View {
        normalModeContent
            .frame(maxHeight: .infinity)
            .padding(0)
            .padding(.leading, store.sidebarVisible ? 0 : trafficLightAreaWidth)
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
    }

    private var normalModeContent: some View {
        HStack(spacing: 12) {
            Menu {
                if store.backHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.backHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: {
                                let originalIndex = store.backHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: true))
                            },
                            label: {
                                Text(historyDisplayName(for: entry))
                            },
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(store.canGoBack ? .primary : .secondary)
            } primaryAction: {
                store.send(.goBack)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoBack)
            .buttonStyle(.borderless)

            Menu {
                if store.forwardHistory.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(store.forwardHistory.enumerated().reversed()), id: \.offset) { index, entry in
                        Button(
                            action: {
                                let originalIndex = store.forwardHistory.count - 1 - index
                                store.send(.goToHistoryIndex(originalIndex, isBackHistory: false))
                            },
                            label: {
                                Text(historyDisplayName(for: entry))
                            },
                        )
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(store.canGoForward ? .primary : .secondary)
            } primaryAction: {
                store.send(.goForward)
            }
            .menuIndicator(.hidden)
            .disabled(!store.canGoForward)
            .buttonStyle(.borderless)

            Button {
                store.send(.goToEnclosingDirectory)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(store.canGoToEnclosingDirectory ? .primary : .secondary)
            }
            .disabled(!store.canGoToEnclosingDirectory)
            .buttonStyle(.borderless)

            Button {
                store.send(.enterComposer)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text(FileManager.default.displayName(atPath: store.currentPath))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isHovered {
                ViewToggleButton(store: store)
                SortGroupButton(store: store)
            }
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
        }
    }
}

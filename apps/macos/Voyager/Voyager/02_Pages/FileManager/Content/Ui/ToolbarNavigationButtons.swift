import ComposableArchitecture
import SwiftUI
import VoyagerShared

struct ToolbarNavigationButtons: View {
    let onNavigationAction: (ContentPageNavigationAction.View) -> Void
    let backHistoryItems: [ToolbarHistoryItem]
    let forwardHistoryItems: [ToolbarHistoryItem]
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoToEnclosingDirectory: Bool

    var body: some View {
        HStack(spacing: 0) {
            backButton()
            forwardButton()
            enclosingDirectoryButton()
        }
    }

    private func backButton() -> some View {
        ToolbarMenuButton(
            systemName: "chevron.left",
            isEnabled: canGoBack,
            font: IconButtonStyle.toolbar.font,
            menuID: backHistoryItems.count,
            primaryAction: { onNavigationAction(.goBack) },
            menuContent: {
                if backHistoryItems.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(backHistoryItems.enumerated().reversed()), id: \.offset) { index, item in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: true))
                            },
                            label: { historyMenuLabel(for: item) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func forwardButton() -> some View {
        ToolbarMenuButton(
            systemName: "chevron.right",
            isEnabled: canGoForward,
            font: IconButtonStyle.toolbar.font,
            menuID: forwardHistoryItems.count,
            primaryAction: { onNavigationAction(.goForward) },
            menuContent: {
                if forwardHistoryItems.isEmpty {
                    Text("No history")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(forwardHistoryItems.enumerated().reversed()), id: \.offset) { index, item in
                        Button(
                            action: {
                                onNavigationAction(.goToHistoryIndex(index, isBackHistory: false))
                            },
                            label: { historyMenuLabel(for: item) },
                        )
                    }
                }
            },
        )
        .fixedSize()
    }

    private func enclosingDirectoryButton() -> some View {
        Button(
            action: { onNavigationAction(.goToEnclosingDirectory) },
            label: {
                ToolbarHoverButtonLabel(
                    systemName: "chevron.up",
                    isEnabled: canGoToEnclosingDirectory,
                    font: IconButtonStyle.toolbar.font,
                )
            },
        )
        .fixedSize()
        .disabled(!canGoToEnclosingDirectory)
        .buttonStyle(.borderless)
    }

    private func historyMenuLabel(for item: ToolbarHistoryItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.iconSystemName)
                .frame(width: 10, height: 10)
            Text(item.title)
        }
    }
}
